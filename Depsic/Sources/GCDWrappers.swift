//
//  GCDWrappers.swift
//  simplecgiapp
//
//  Created by depinette on 23/01/2016.
//  Copyright © 2016 depsys. All rights reserved.
//

import Foundation
#if os(Linux)
    import CDispatch
#endif

//This is to wrap dispatch_xxx_f() version of the API using callbacks in my_dispatch_xxx() using blocks
//Can be removed when GCD is distributed with block support on Linux

//idiotic version of https://bugs.swift.org/browse/SR-577?focusedCommentId=11772&page=com.atlassian.jira.plugin.system.issuetabpanels:comment-tabpanel#comment-11772

public typealias Block = () -> Void

private func dispatched_func(pointer: UnsafeMutablePointer<Void>)
{
    let unmanaged = Unmanaged<BlockBox>.fromOpaque(COpaquePointer(pointer))
    unmanaged.takeRetainedValue().block()
}

private final class BlockBox
{
    let block: Block
    init(_ block: Block)
    {
        self.block = block
    }
}

private func BlockCopy(block: Block) -> UnsafeMutablePointer<Void>
{
    let opaque = Unmanaged.passRetained(BlockBox(block)).toOpaque()
    return UnsafeMutablePointer<Void>(opaque)
}

internal func my_dispatch_async(queue: dispatch_queue_t, _ block: Block)
{
   dispatch_async_f(queue, BlockCopy(block), dispatched_func)
}

internal func my_dispatch_group_async(group: dispatch_group_t, _ queue: dispatch_queue_t, _ block: Block)
{
    dispatch_group_async_f(group, queue, BlockCopy(block), dispatched_func)
}

/*
internal func my_dispatch_source_set_event_handler(source: dispatch_source_t, _ block: Block)
{
    dispatch_set_context(source, BlockCopy(block));
    dispatch_source_set_event_handler_f(source, dispatched_func);
}
*/

internal func my_dispatch_after(when: dispatch_time_t, _ queue: dispatch_queue_t, _ block: Block)
{
    dispatch_after_f(when, queue, BlockCopy(block), dispatched_func)
}

