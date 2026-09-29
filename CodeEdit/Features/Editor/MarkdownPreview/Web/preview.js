// Offline Markdown preview.
// markdown-it 14.1.0, DOMPurify 3.2.6, highlight.js 11.11.1, KaTeX 0.16.25, Mermaid 11.12.0.

let generation = 0
let markdown

const ALERT_TITLES = {
  note: "Note",
  tip: "Tip",
  important: "Important",
  warning: "Warning",
  caution: "Caution"
}

const PURIFY_CONFIG = {
  ADD_TAGS: ["input"],
  ADD_ATTR: ["align", "width", "height", "valign", "disabled", "checked", "type"],
  FORBID_TAGS: ["script", "iframe", "object", "embed", "link", "meta"]
}

function highlightCode(source, lang) {
  const escape = markdown.utils.escapeHtml
  const language = (lang || "").toLowerCase()
  if (language === "mermaid") {
    return `<pre class="mermaid-source"><code class="language-mermaid">${escape(source)}</code></pre>`
  }
  if (language && window.hljs.getLanguage(language)) {
    try {
      const value = window.hljs.highlight(source, { language, ignoreIllegals: true }).value
      return `<pre class="hljs"><code class="hljs language-${escape(language)}">${value}</code></pre>`
    } catch (_) {
      // Fall through to plain text.
    }
  }
  return `<pre class="hljs"><code class="hljs">${escape(source)}</code></pre>`
}

function githubSlug(value) {
  return value
    .toLowerCase()
    .trim()
    .replace(/[\u2000-\u206F\u2E00-\u2E7F\\'!"#$%&()*+,./:;<=>?@[\]^`{|}~]/g, "")
    .replace(/\s/g, "-")
}

function headingAnchors(instance) {
  instance.core.ruler.push("heading-anchors", (state) => {
    const seen = Object.create(null)
    const tokens = state.tokens
    for (let index = 0; index < tokens.length - 1; index++) {
      if (tokens[index].type !== "heading_open") continue
      const inline = tokens[index + 1]
      if (!inline || inline.type !== "inline") continue
      let slug = githubSlug(inline.content) || "section"
      const base = slug
      let count = 0
      while (seen[slug]) {
        count += 1
        slug = `${base}-${count}`
      }
      seen[slug] = true
      tokens[index].attrSet("id", slug)
    }
  })
}

function taskLists(instance) {
  instance.core.ruler.after("inline", "task-lists", (state) => {
    const tokens = state.tokens
    for (let index = 2; index < tokens.length; index++) {
      markTaskItem(state, tokens, index)
    }
  })
}

function markTaskItem(state, tokens, index) {
  const token = tokens[index]
  if (token.type !== "inline") return
  if (tokens[index - 1].type !== "paragraph_open") return
  if (tokens[index - 2].type !== "list_item_open") return
  const match = /^\[([ xX])\][ \t]+/.exec(token.content)
  if (!match || !token.children || !token.children.length) return
  const checked = match[1].toLowerCase() === "x"
  token.content = token.content.slice(match[0].length)
  if (token.children[0].type === "text") {
    token.children[0].content = token.children[0].content.replace(/^\[([ xX])\][ \t]+/, "")
  }
  const checkbox = new state.Token("html_inline", "", 0)
  checkbox.content = `<input type="checkbox" disabled${checked ? " checked" : ""}> `
  token.children.unshift(checkbox)
  tokens[index - 2].attrJoin("class", "task-list-item")
}

function githubAlerts(instance) {
  instance.core.ruler.after("block", "github-alerts", (state) => {
    const tokens = state.tokens
    for (let index = 0; index < tokens.length; index++) {
      if (tokens[index].type === "blockquote_open") convertAlert(tokens, index)
    }
  })
}

function convertAlert(tokens, openIndex) {
  const closeIndex = matchingClose(tokens, openIndex)
  if (closeIndex < 0) return
  const inline = tokens.slice(openIndex + 1, closeIndex).find((token) => token.type === "inline")
  if (!inline) return
  const match = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\n?/.exec(inline.content)
  if (!match) return
  const kind = match[1].toLowerCase()
  inline.content = inline.content.slice(match[0].length)
  stripAlertMarker(inline)
  const title = ALERT_TITLES[kind]
  tokens[openIndex].type = "html_block"
  tokens[openIndex].nesting = 0
  tokens[openIndex].content =
    `<div class="markdown-alert markdown-alert-${kind}"><p class="markdown-alert-title">${title}</p>\n`
  tokens[closeIndex].type = "html_block"
  tokens[closeIndex].nesting = 0
  tokens[closeIndex].content = "</div>\n"
}

function matchingClose(tokens, openIndex) {
  let depth = 0
  for (let index = openIndex; index < tokens.length; index++) {
    if (tokens[index].type === "blockquote_open") depth += 1
    if (tokens[index].type === "blockquote_close") {
      depth -= 1
      if (depth === 0) return index
    }
  }
  return -1
}

function stripAlertMarker(inline) {
  if (!inline.children || !inline.children.length) return
  const first = inline.children[0]
  if (first.type === "text") {
    first.content = first.content.replace(/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*\n?/, "")
    if (!first.content) inline.children.shift()
  }
  if (inline.children[0] && inline.children[0].type === "softbreak") inline.children.shift()
}

function stashMath(slots, tex, display) {
  const id = slots.length
  slots.push({ tex: tex.trim(), display })
  return `%%MATH${id}%%`
}

function protectMath(source) {
  const slots = []
  let output = ""
  let index = 0
  while (index < source.length) {
    const fence = fenceAt(source, index)
    if (fence) {
      const info = fence.info.trim().split(/\s+/)[0].toLowerCase()
      output += info === "math" || info === "katex" ? stashMath(slots, fence.body, true) : fence.raw
      index = fence.end
      continue
    }
    const code = inlineCodeAt(source, index)
    if (code) {
      output += code.raw
      index = code.end
      continue
    }
    const next = nextCode(source, index)
    output += replaceMath(source.slice(index, next), slots)
    if (next <= index) {
      output += source[index]
      index += 1
    } else {
      index = next
    }
  }
  return { text: output, slots }
}

function fenceAt(source, index) {
  if (index > 0 && source[index - 1] !== "\n") return null
  const marker = source.startsWith("```", index) ? "```" : source.startsWith("~~~", index) ? "~~~" : null
  if (!marker) return null
  const lineEnd = source.indexOf("\n", index)
  if (lineEnd < 0) return null
  const closeAt = source.indexOf(`\n${marker}`, lineEnd + 1)
  if (closeAt < 0) return null
  return {
    raw: source.slice(index, closeAt + 1 + marker.length),
    body: source.slice(lineEnd + 1, closeAt),
    info: source.slice(index + marker.length, lineEnd),
    end: closeAt + 1 + marker.length
  }
}

function inlineCodeAt(source, index) {
  if (source[index] !== "`") return null
  let ticks = 0
  while (source[index + ticks] === "`") ticks += 1
  const end = source.indexOf("`".repeat(ticks), index + ticks)
  if (end < 0) return null
  return { raw: source.slice(index, end + ticks), end: end + ticks }
}

function nextCode(source, index) {
  let next = source.length
  const fence = source.indexOf("\n```", index)
  const tilde = source.indexOf("\n~~~", index)
  const tick = source.indexOf("`", index)
  if (fence >= 0) next = Math.min(next, fence + 1)
  if (tilde >= 0) next = Math.min(next, tilde + 1)
  if (tick >= 0) next = Math.min(next, tick)
  return next
}

function replaceMath(text, slots) {
  let value = text
  value = value.replace(/\\\[([\s\S]+?)\\\]/g, (_, tex) => stashMath(slots, tex, true))
  value = value.replace(/\$\$([\s\S]+?)\$\$/g, (_, tex) => stashMath(slots, tex, true))
  value = value.replace(/\\\(([\s\S]+?)\\\)/g, (_, tex) => stashMath(slots, tex, false))
  value = value.replace(/(^|[^\\$])\$(?!\$)(\S(?:\\.|[^$\n])*?\S|\S)\$(?!\$)/g, (full, pre, tex) => {
    return pre + stashMath(slots, tex, false)
  })
  return value
}

function renderKatex(slots, html) {
  return html.replace(/%%MATH(\d+)%%/g, (_, id) => {
    const slot = slots[Number(id)]
    if (!slot) return ""
    try {
      return window.katex.renderToString(slot.tex, {
        displayMode: slot.display,
        throwOnError: false,
        strict: "ignore",
        trust: false
      })
    } catch (_) {
      return `<code>${markdown.utils.escapeHtml(slot.tex)}</code>`
    }
  })
}

function renderToHTML(source) {
  const protectedSource = protectMath(source)
  let html = markdown.render(protectedSource.text)
  html = renderKatex(protectedSource.slots, html)
  return window.DOMPurify.sanitize(html, PURIFY_CONFIG)
}

function rewriteResources(root) {
  root.querySelectorAll("[src], a[href]").forEach((element) => {
    if (element.hasAttribute("src")) rewriteAttribute(element, "src")
    if (element.hasAttribute("href")) rewriteAttribute(element, "href")
  })
}

function rewriteAttribute(element, attribute) {
  const value = element.getAttribute(attribute)
  if (!value || value.startsWith("#")) return
  if (value.startsWith("//")) {
    element.setAttribute(attribute, `https:${value}`)
    return
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return
  element.setAttribute(attribute, `cemd://asset/?ref=${encodeURIComponent(value)}`)
}

function applyScheme(scheme) {
  const dark = scheme === "dark"
  document.documentElement.style.colorScheme = dark ? "dark" : "light"
  document.body.style.background = dark ? "#0d1117" : "#ffffff"
  document.getElementById("md-light").disabled = dark
  document.getElementById("md-dark").disabled = !dark
  document.getElementById("hljs-light").disabled = dark
  document.getElementById("hljs-dark").disabled = !dark
}

async function renderMermaid(root, scheme, token) {
  const codes = [...root.querySelectorAll("code.language-mermaid")]
  if (!codes.length || !window.mermaid) return
  window.mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: scheme === "dark" ? "dark" : "default",
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
  })
  for (const code of codes) {
    if (token !== generation || !code.isConnected) return
    const pre = code.parentElement
    const id = `mmd${Math.random().toString(36).slice(2)}`
    try {
      const result = await window.mermaid.render(id, code.textContent)
      if (token !== generation || !code.isConnected) {
        removeStray(id)
        return
      }
      const holder = document.createElement("div")
      holder.className = "mermaid"
      holder.innerHTML = result.svg
      pre.replaceWith(holder)
      if (typeof result.bindFunctions === "function") result.bindFunctions(holder)
      removeStray(id, holder)
    } catch (_) {
      removeStray(id)
    }
  }
}

function removeStray(id, holder) {
  const stray = document.getElementById(id)
  if (stray && (!holder || !holder.contains(stray))) stray.remove()
}

function librariesReady() {
  return window.markdownit && window.DOMPurify && window.hljs && window.katex
}

function installMarkdown() {
  if (!librariesReady() || markdown) return
  markdown = window.markdownit({
    html: true,
    linkify: true,
    typographer: false,
    highlight: highlightCode
  })
  markdown.use(githubAlerts)
  markdown.use(taskLists)
  markdown.use(headingAnchors)
}

window.renderMarkdown = async function renderMarkdown(source, scheme) {
  const token = ++generation
  const colorScheme = scheme === "dark" ? "dark" : "light"
  applyScheme(colorScheme)
  const content = document.getElementById("content")
  installMarkdown()
  if (!markdown) {
    content.textContent = "Markdown preview failed to load."
    return content.innerHTML
  }
  const html = renderToHTML(source || "")
  if (token !== generation) return content.innerHTML
  content.innerHTML = html
  rewriteResources(content)
  await renderMermaid(content, colorScheme, token)
  return content.innerHTML
}

window.addEventListener("error", (event) => {
  document.body.setAttribute("data-preview-error", String(event.message || "error"))
})
