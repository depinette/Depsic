//
//  Package.swift
//  fastcgiapp
//
//  Created by depinette on 06/01/2016.
//  Copyright © 2016 fkdev. All rights reserved.
//

import PackageDescription

let package = Package(
    name: "simplecgiapp",
    dependencies: [.Package(url: "../CDispatch", majorVersion: 1)]
)