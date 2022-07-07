//
// HTTPFileUploadHelper.swift
//
// Siskin IM
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import Foundation
import TigaseSwift
import TigaseLogging

open class HTTPFileUploadHelper {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HTTPFileUploadHelper")
    
    public static func upload(for context: Context, filename: String, inputStream: InputStream, filesize size: Int, mimeType: String, delegate: URLSessionDelegate?) async throws -> URL {
        let httpUploadModule = context.module(.httpFileUpload);
        let components = try await httpUploadModule.findHttpUploadComponents();
        guard let component = components.first(where: { $0.maxSize > size }) else {
            throw ShareError.fileTooBig;
        }

        let slot = try await httpUploadModule.requestUploadSlot(componentJid: component.jid, filename: filename, size: size, contentType: mimeType);
        
        var request = URLRequest(url: slot.putUri);
        slot.putHeaders.forEach({ (k,v) in
            request.addValue(v, forHTTPHeaderField: k);
        });
        request.httpMethod = "PUT";
        request.httpBodyStream = inputStream;
        request.addValue(String(size), forHTTPHeaderField: "Content-Length");
        request.addValue(mimeType, forHTTPHeaderField: "Content-Type");
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: delegate, delegateQueue: OperationQueue.main);
        return try await withUnsafeThrowingContinuation({ continuation in
            session.dataTask(with: request) { (data, response, error) in
                let code = (response as? HTTPURLResponse)?.statusCode ?? 500;
                guard error == nil && (code == 200 || code == 201) else {
                    logger.error("upload of file \(filename) failed, error: \(error as Any), response: \(response as Any)");
                    continuation.resume(throwing: ShareError.httpError);
                    return;
                }
                if code == 200 {
                    continuation.resume(throwing: ShareError.invalidResponseCode(url: slot.getUri));
                } else {
                    continuation.resume(returning: slot.getUri);
                }
            }.resume()
        })
    }
    
//    public enum UploadResult {
//        case success(url: URL, filesize: Int, mimeType: String?)
//        case failure(ShareError)
//    }
}

public struct FileUpload {
    public let url: URL;
    public let filesize: Int;
    public let mimeType: String?;
    
    public init(url: URL, filesize: Int, mimeType: String?) {
        self.url = url;
        self.filesize = filesize;
        self.mimeType = mimeType;
    }
}

