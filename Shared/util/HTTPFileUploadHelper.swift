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
    
    public static func upload(for context: Context, filename: String, inputStream: InputStream, filesize size: Int, mimeType: String, delegate: URLSessionDelegate?, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        let httpUploadModule = context.module(.httpFileUpload);
        httpUploadModule.findHttpUploadComponent(completionHandler: { result in
            switch result {
            case .success(let components):
                guard let component = components.first(where: { $0.maxSize > size }) else {
                    completionHandler(.failure(.fileTooBig));
                    return;
                }
                httpUploadModule.requestUploadSlot(componentJid: component.jid, filename: filename, size: size, contentType: mimeType, completionHandler: { result in
                    switch result {
                    case .success(let slot):
                        var request = URLRequest(url: slot.putUri);
                        slot.putHeaders.forEach({ (k,v) in
                            request.addValue(v, forHTTPHeaderField: k);
                        });
                        request.httpMethod = "PUT";
                        request.httpBodyStream = inputStream;
                        request.addValue(String(size), forHTTPHeaderField: "Content-Length");
                        request.addValue(mimeType, forHTTPHeaderField: "Content-Type");
                        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: delegate, delegateQueue: OperationQueue.main);
                        session.dataTask(with: request) { (data, response, error) in
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 500;
                            guard error == nil && (code == 200 || code == 201) else {
                                logger.error("upload of file \(filename) failed, error: \(error as Any), response: \(response as Any)");
                                completionHandler(.failure(.httpError));
                                return;
                            }
                            if code == 200 {
                                completionHandler(.failure(.invalidResponseCode(url: slot.getUri)));
                            } else {
                                completionHandler(.success(slot.getUri));
                            }
                        }.resume();
                    case .failure(let error):
                        logger.error("upload of file \(filename) failed, upload component returned error: \(error as Any)");
                        completionHandler(.failure(.unknownError));
                    }
                });
            case .failure(let error):
                completionHandler(.failure(error.errorCondition == .item_not_found ? .notSupported : .unknownError));
            }
        })
    }
    
    public enum UploadResult {
        case success(url: URL, filesize: Int, mimeType: String?)
        case failure(ShareError)
    }
}
