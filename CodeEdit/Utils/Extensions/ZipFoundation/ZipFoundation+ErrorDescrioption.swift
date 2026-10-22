//
//  ZipFoundation+ErrorDescrioption.swift
//  CodeEdit
//
//  Created by Khan Winter on 8/14/25.
//

import Foundation
import ZIPFoundation

extension Archive.ArchiveError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadableArchive:
            String(localized: "Unreadable archive.")
        case .unwritableArchive:
            String(localized: "Unwritable archive.")
        case .invalidEntryPath:
            String(localized: "Invalid entry path.")
        case .invalidCompressionMethod:
            String(localized: "Invalid compression method.")
        case .invalidCRC32:
            String(localized: "Invalid checksum.")
        case .cancelledOperation:
            String(localized: "Operation cancelled.")
        case .invalidBufferSize:
            String(localized: "Invalid buffer size.")
        case .invalidEntrySize:
            String(localized: "Invalid entry size.")
        case .invalidLocalHeaderDataOffset,
                .invalidLocalHeaderSize,
                .invalidCentralDirectoryOffset,
                .invalidCentralDirectorySize,
                .invalidCentralDirectoryEntryCount,
                .missingEndOfCentralDirectoryRecord:
            String(localized: "Invalid file detected.")
        case .uncontainedSymlink:
            String(localized: "Uncontained symlink detected.")
        }
    }

    public var failureReason: String? {
        return switch self {
        case .invalidLocalHeaderDataOffset:
            String(localized: "Invalid local header data offset.")
        case .invalidLocalHeaderSize:
            String(localized: "Invalid local header size.")
        case .invalidCentralDirectoryOffset:
            String(localized: "Invalid central directory offset.")
        case .invalidCentralDirectorySize:
            String(localized: "Invalid central directory size.")
        case .invalidCentralDirectoryEntryCount:
            String(localized: "Invalid central directory entry count.")
        case .missingEndOfCentralDirectoryRecord:
            String(localized: "Missing end of central directory record.")
        default:
            nil
        }
    }
}
