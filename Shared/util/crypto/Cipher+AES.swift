//
// Cipher+AES.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import OpenSSL
import TigaseLogging

open class Cipher {
    
}

extension Cipher {

    open class AES_GCM {
        
        private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "aesgcm")
        
        public init() {
            
        }
        
        public static func generateKey(ofSize: Int) -> Data? {
            var key = Data(count: ofSize/8);
            let result = key.withUnsafeMutableBytes({ (ptr: UnsafeMutableRawBufferPointer) -> Int32 in
                return SecRandomCopyBytes(kSecRandomDefault, ofSize/8, ptr.baseAddress!);
            });
            guard result == errSecSuccess else {
                AES_GCM.logger.error("failed to generated AES encryption key: \(result)");
                return nil;
            }
            return key;
        }
        
        open func encrypt(iv: Data, key: Data, message data: Data, output: UnsafeMutablePointer<Data>?, tag: UnsafeMutablePointer<Data>?) -> Bool {
            let ctx = EVP_CIPHER_CTX_new();
            
            EVP_EncryptInit_ex(ctx, key.count == 32 ? EVP_aes_256_gcm() : EVP_aes_128_gcm(), nil, nil, nil);
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, Int32(iv.count), nil);
            iv.withUnsafeBytes({ (ivBytes: UnsafeRawBufferPointer) -> Void in
                key.withUnsafeBytes({ (keyBytes: UnsafeRawBufferPointer) -> Void in
                    EVP_EncryptInit_ex(ctx, nil, nil, keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
                })
            });
            EVP_CIPHER_CTX_set_padding(ctx, 1);
            
            var outbuf = Array(repeating: UInt8(0), count: data.count);
            var outbufLen: Int32 = 0;
            
            let encryptedBody = data.withUnsafeBytes { ( bytes) -> Data in
                EVP_EncryptUpdate(ctx, &outbuf, &outbufLen, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(data.count));
                return Data(bytes: &outbuf, count: Int(outbufLen));
            }
            
            EVP_EncryptFinal_ex(ctx, &outbuf, &outbufLen);
            
            var tagData = Data(count: 16);
            tagData.withUnsafeMutableBytes({ (bytes) -> Void in
                EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
            });
            
            EVP_CIPHER_CTX_free(ctx);
            
            tag?.initialize(to: tagData);
            output?.initialize(to: encryptedBody);
            return true;
        }
        
        open func encrypt(iv: Data, key: Data, provider: CipherDataProvider, consumer: CipherDataConsumer, chunkSize: Int = 512*1024) -> Data {
            let ctx = EVP_CIPHER_CTX_new();
        
            EVP_EncryptInit_ex(ctx, key.count == 32 ? EVP_aes_256_gcm() : EVP_aes_128_gcm(), nil, nil, nil);
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, Int32(iv.count), nil);
            iv.withUnsafeBytes({ (ivBytes: UnsafeRawBufferPointer) -> Void in
                key.withUnsafeBytes({ (keyBytes: UnsafeRawBufferPointer) -> Void in
                    EVP_EncryptInit_ex(ctx, nil, nil, keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
                })
            });
            EVP_CIPHER_CTX_set_padding(ctx, 1);
        
            var ended: Bool = false;
            var buffer = Data(count: chunkSize * 2);
            repeat {
                switch provider.chunk(size: chunkSize) {
                case .data(let data):
                    let result = data.withUnsafeBytes { ( bytes) -> Data in
                        let wrote = buffer.withUnsafeMutableBytes { (outbuf) -> Int in
                            var outbufLen: Int32 = 0;
                            EVP_EncryptUpdate(ctx, outbuf.baseAddress!.assumingMemoryBound(to: UInt8.self), &outbufLen, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(data.count));
                            return Int(outbufLen)
                        }
                        return buffer.subdata(in: 0..<wrote);
                    }
                    _ = consumer.consume(data: result);
                case .ended:
                    buffer.withUnsafeMutableBytes { (outbuf) -> Void in
                        var outbufLen: Int32 = 0;
                        EVP_EncryptFinal_ex(ctx, outbuf.baseAddress!.assumingMemoryBound(to: UInt8.self), &outbufLen);
                        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, outbuf.baseAddress!.assumingMemoryBound(to: UInt8.self));
                    }
                    ended = true;
                }
            } while !ended;
            
            return buffer.subdata(in: 0..<16);
        }
                
        open func decrypt(iv: Data, key: Data, encoded payload: Data, auth tag: Data?, output: UnsafeMutablePointer<Data>?) -> Bool {
            
            let ctx = EVP_CIPHER_CTX_new();
            EVP_DecryptInit_ex(ctx, key.count == 32 ? EVP_aes_256_gcm() : EVP_aes_128_gcm(), nil, nil, nil);
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, Int32(iv.count), nil);
            key.withUnsafeBytes({ (keyBytes) -> Void in
                iv.withUnsafeBytes({ (ivBytes) -> Void in
                    EVP_DecryptInit_ex(ctx, nil, nil, keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
                })
            })
            EVP_CIPHER_CTX_set_padding(ctx, 1);
            
            var auth = tag;
            var encoded = payload;
            if auth == nil {
                auth = payload.subdata(in: (payload.count - 16)..<payload.count);
                encoded = payload.subdata(in: 0..<(payload.count-16));
            }
            
            var outbuf = Array(repeating: UInt8(0), count: encoded.count);
            var outbufLen: Int32 = 0;
            let decoded = encoded.withUnsafeBytes({ (bytes) -> Data in
                EVP_DecryptUpdate(ctx, &outbuf, &outbufLen, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(encoded.count));
                return Data(bytes: &outbuf, count: Int(outbufLen));
            });
            
            if auth != nil {
                auth!.withUnsafeMutableBytes({ [count = auth!.count] (bytes: UnsafeMutableRawBufferPointer) -> Void in
                    EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_CCM_SET_TAG, Int32(count), bytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
                });
            }
            
            let ret = EVP_DecryptFinal_ex(ctx, &outbuf, &outbufLen);
            EVP_CIPHER_CTX_free(ctx);
            guard ret >= 0 else {
                AES_GCM.logger.error("authentication of encrypted message failed: \(ret)");
                return false;
            }
            
            output?.initialize(to: decoded);
            return true;
        }
        
        open func decrypt(iv: Data, key: Data, provider: CipherDataProvider, consumer: CipherDataConsumer, chunkSize: Int = 512 * 1024) -> Bool {
            let ctx = EVP_CIPHER_CTX_new();
            EVP_DecryptInit_ex(ctx, key.count == 32 ? EVP_aes_256_gcm() : EVP_aes_128_gcm(), nil, nil, nil);
            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, Int32(iv.count), nil);
            key.withUnsafeBytes({ (keyBytes) -> Void in
                iv.withUnsafeBytes({ (ivBytes) -> Void in
                    EVP_DecryptInit_ex(ctx, nil, nil, keyBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), ivBytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
                })
            })
            EVP_CIPHER_CTX_set_padding(ctx, 1);
            
            var ended: Bool = false;
            var buffer = Data(count: chunkSize * 2);
            var result = false;
            repeat {
                switch provider.chunk(size: chunkSize) {
                case .data(let data):
                    let result = data.withUnsafeBytes { ( bytes) -> Data in
                        let wrote = buffer.withUnsafeMutableBytes { (outbuf) -> Int in
                            var outbufLen: Int32 = 0;
                            EVP_DecryptUpdate(ctx, outbuf.baseAddress!.assumingMemoryBound(to: UInt8.self), &outbufLen, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), Int32(data.count));
                            return Int(outbufLen)
                        }
                        return buffer.subdata(in: 0..<wrote);
                    }
                    _ = consumer.consume(data: result);
                case .ended:
                    if var auth = (provider as? CipherDataProviderWithAuth)?.authTag() {
                        auth.withUnsafeMutableBytes({ [count = auth.count] (bytes: UnsafeMutableRawBufferPointer) -> Void in
                            EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_CCM_SET_TAG, Int32(count), bytes.baseAddress!.assumingMemoryBound(to: UInt8.self));
                        });
                    }
                    result = buffer.withUnsafeMutableBytes { (outbuf) -> Bool in
                        var outbufLen: Int32 = 0;
                        return EVP_DecryptFinal_ex(ctx, outbuf.baseAddress!.assumingMemoryBound(to: UInt8.self), &outbufLen) >= 0;
                    }
                    ended = true;
                }
            } while !ended;
            
            return result;
        }
        
    }
            
    public class DataDataProvider: CipherDataProvider {
        
        let data: Data;
        private(set) var offset:  Int = 0;
        
        public init(data: Data) {
            self.data = data;
        }
        
        public func chunk(size chunkSize: Int) -> Cipher.DataProviderResult {
            guard offset < data.count else {
                return .ended;
            }
            let size = min(chunkSize, data.count - offset);
            defer {
                offset = offset + size;
            }
            return .data(data.subdata(in: offset..<(offset + size)));
        }
        
    }
    
    public class FileDataProvider: CipherDataProviderWithAuth {
        
        let inputStream: InputStream;

        var count: Int = 0;
        var limit: Int = 0;

        public convenience init(inputStream: InputStream, fileSize: Int, hasAuthTag: Bool) {
            if hasAuthTag {
                self.init(inputStream: inputStream, limit: fileSize - 16);
            } else {
                self.init(inputStream: inputStream);
            }
        }
        
        public init(inputStream: InputStream, limit: Int = Int.max) {
            self.limit = limit;
            self.inputStream = inputStream;
            self.inputStream.open();
        }
        
        deinit {
            self.inputStream.close();
        }
        
        public func chunk(size: Int) -> Cipher.DataProviderResult {
            guard inputStream.hasBytesAvailable else {
                inputStream.close();
                return .ended;
            }
            
            let limit = min(size, self.limit - self.count);
            guard limit > 0 else {
                return .ended;
            }
            
            var buf = Array(repeating: UInt8(0), count: limit);
            let read = inputStream.read(&buf, maxLength: limit);
            guard read > 0 else {
                return .ended;
            }
            count = count + read;
            return .data(Data(bytes: &buf, count: read));
        }
        
        public func authTag() -> Data? {
            guard inputStream.hasBytesAvailable else {
                return nil;
            }
            var buf = Array(repeating: UInt8(0), count: 16);
            let read = inputStream.read(&buf, maxLength: 16);
            guard read > 0 else {
                return nil;
            }
            return Data(bytes: &buf, count: read);
        }
        
    }
    
    public class TempFileConsumer: CipherDataConsumer {
        
        public let url: URL;
        private var outputStream: OutputStream?;
        public private(set) var size: Int = 0;
        
        public init?() {
            self.url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);
            guard let outputStream = OutputStream(url: url, append: true) else {
                return nil;
            }
            self.outputStream = outputStream;
            self.outputStream?.open();
            guard self.outputStream != nil, self.outputStream!.hasSpaceAvailable else {
                return nil;
            }
        }
        
        public func consume(data: Data) -> Int {
            let wrote = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                return outputStream!.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: data.count);
            }
            size = size + wrote;
            return wrote;
        }
        
        public func close() {
            self.outputStream!.close();
        }
        
        deinit {
            if outputStream != nil {
                outputStream?.close();
            }
            try? FileManager.default.removeItem(at: url);
        }
        
    }
    
    public enum DataProviderResult {
        case data(Data)
        case ended
    }
}

public protocol CipherDataProvider {
    
    func chunk(size: Int) -> Cipher.DataProviderResult;
    
}

public protocol CipherDataProviderWithAuth: CipherDataProvider {
    
    func authTag() -> Data?;
    
}

public protocol CipherDataConsumer {
    
    func consume(data: Data) -> Int;
    
}
