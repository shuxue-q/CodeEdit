//
//  ExtensionSceneView.swift
//  CodeEdit
//
//  Created by Wouter Hennen on 31/12/2022.
//

import SwiftUI
import CodeEditKit
import ExtensionKit
import ExtensionFoundation

struct ExtensionSceneView: NSViewControllerRepresentable {

    @Environment(\.openWindow)
    var openWindow

    let appExtension: AppExtensionIdentity
    let sceneID: String

    init(with appExtension: AppExtensionIdentity, sceneID: String) {
        self.appExtension = appExtension
        self.sceneID = sceneID
    }

    func makeNSViewController(context: Context) -> EXHostViewController {
        let controller = EXHostViewController()
        controller.delegate = context.coordinator
        controller.configuration = .some(.init(appExtension: appExtension, sceneID: sceneID))
        context.coordinator.updateEnvironment(context.environment._ceEnvironment)
        return controller
    }

    func updateNSViewController(_ nsViewController: EXHostViewController, context: Context) {
        nsViewController.configuration = .init(appExtension: appExtension, sceneID: sceneID)
        context.coordinator.updateEnvironment(context.environment._ceEnvironment)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator { id in
            print(id)
            DispatchQueue.main.async {
                openWindow(id: id)
            }
        }
    }

    class Coordinator: NSObject, EXHostViewControllerDelegate, EnvironmentPublisherObjc {
        var isOnline: Bool = false
        var toPublish: Data?
        var openWindow: (String) -> Void

        init(openWindow: @escaping (String) -> Void) {
            self.openWindow = openWindow
        }

        var connection: NSXPCConnection?

        /// Builds the `EnvironmentPublisherObjc` interface with `NSData` declared as the only allowed class for the
        /// `data` argument. Swift `Data` is exposed to XPC as a plain object, so without this Foundation falls back
        /// to an `NSObject` allow-list and logs a fault.
        static func makeEnvironmentInterface() -> NSXPCInterface {
            let interface = NSXPCInterface(with: EnvironmentPublisherObjc.self)
            interface.setClasses(
                NSSet(object: NSData.self) as? Set<AnyHashable> ?? [],
                for: #selector(EnvironmentPublisherObjc.publishEnvironment(data:)),
                argumentIndex: 0,
                ofReply: false
            )
            return interface
        }

        func publishEnvironment(data: Data) {
            guard let decodedCallbacks = try? JSONDecoder().decode(Callbacks.self, from: data) else { return }
            switch decodedCallbacks {
            case .openWindow(let id):
                openWindow(id)
            }
        }

        func updateEnvironment(_ value: _CEEnvironment) {
            guard let newEnvironmentData = try? JSONEncoder().encode(value) else { return }

            guard isOnline else {
                toPublish = newEnvironmentData
                return
            }

            Task {
                do {
                    try await connection!.withService { (service: EnvironmentPublisherObjc) in
                        service.publishEnvironment(data: newEnvironmentData)
                    }
                } catch {
                    print(error)
                }
            }
        }

        func hostViewControllerWillDeactivate(_ viewController: EXHostViewController, error: Error?) {
            isOnline = false
            print("Host will deactivate", error as Any)
        }

        func hostViewControllerDidActivate(_ viewController: EXHostViewController) {
            isOnline = true
            do {
                self.connection = try viewController.makeXPCConnection()
                connection?.exportedInterface = Self.makeEnvironmentInterface()
                connection?.exportedObject = self
                connection?.remoteObjectInterface = Self.makeEnvironmentInterface()
                connection?.resume()
                if let toPublish {
                    Task {
                        try? await connection?.withService { (service: EnvironmentPublisherObjc) in
                            service.publishEnvironment(data: toPublish)
                        }
                    }
                }
            } catch {
                print("Unable to create connection: \(String(describing: error))")
            }
        }
    }
}
