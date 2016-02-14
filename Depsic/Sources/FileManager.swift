//
//  NSFileManager+Util.swift
//  simplecgiapp
//
//  Created by depinette on 16/01/2016.
//  Copyright © 2016 fkdev. All rights reserved.
//

import Foundation
#if os(Linux)
    import Glibc
    import CDispatch
#else
    import Darwin
#endif

let FileError:UnsafeMutablePointer<FILE> = nil
class FileManager
{
    private func writeBodyPartToFile(buffer:ArraySlice<UInt8>, path:String)
    {
        let fp = fopen(path, "w"); defer {fclose(fp)}
        if  fp == FileError
        {
            print("error \(errno) while fopen 'w' \(path)")
            return
        }
        var theBuffer = buffer
        let count = withUnsafePointer(&theBuffer)
            {
                fwrite($0, sizeof(CChar), buffer.count, fp)
        }
        if count != buffer.count {
            print("error \(errno) while write body beginning to file \(path)")
        }
    }
    
    static internal func createTempDirectory(subDirectoryPath:String?) -> String?
    {
        /*
        var tempDirURL = NSURL(fileURLWithPath: NSTemporaryDirectory())
        if let subDirPath = subDirectoryPath
        {
            tempDirURL = tempDirURL.URLByAppendingPathComponent(subDirPath)
        }
        
        do
        {
            try NSFileManager.defaultManager().createDirectoryAtURL(tempDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
        
        return tempDirURL.absoluteString
*/
        return ""
    }

    static internal func openTempFile()
    {
        /*
        // The template string:
        let template = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("simplecgiapp.XXXXXX")
        
        // Fill buffer with a C string representing the local file system path.
        var buffer = [Int8](count: Int(PATH_MAX), repeatedValue: 0)
        template.getFileSystemRepresentation(&buffer, maxLength: buffer.count)
        
        // Create unique file name (and open file):
        let fd = mkstemp(&buffer)
        if fd != -1 {
            
            // Create URL from file system string:
            let url = NSURL(fileURLWithFileSystemRepresentation: buffer, isDirectory: false, relativeToURL: nil)
            print(url.path!)
            
        } else {
            print("Error: " + String(strerror(errno)))
        }*/
    }

}