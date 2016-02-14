//
//  SocketServer.swift
//  Depsic
//
//  Created by depinette on 02/01/2016.
//  Copyright © 2016 depsys. All rights reserved.
//  Socket-base servers.
//  Create a server (e.g. IPV4SocketServet and give it a delegate).
//  You will have to provide a delegate for each connection accepted.

import Foundation
#if os(Linux)
    import Glibc
    import CDispatch
#else
    import Darwin
#endif

typealias SunPathType = (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8)
typealias SocketDescriptorType = Int32
typealias SocketReturnType = Int32

let SocketSuccess:Int32 = 0
let SocketError:Int32 = -1
var shutdownAsked: sig_atomic_t = 0
let ReadTimeoutInSec:Float = 3

public protocol SocketServerDelegate : class
{
    func didAcceptClient(connectedClient:ConnectedClient)
    func didDisconnectClient(connectedClient:ConnectedClient)
}

public protocol ConnectedClientDelegate
{
    func didReceiveData(connectedClient:ConnectedClient, buffer:[UInt8])
    func didDisconnect(connectedClient:ConnectedClient)
}

//enhancements to sockaddr_xxx structures
private protocol SockaddrAdditions
{
    func toSockaddr() -> sockaddr
    func length() -> socklen_t
}
extension SockaddrAdditions
{
    func toSockaddr()->sockaddr {
        var this = self;
        return withUnsafePointer(&this, {UnsafePointer($0)}).memory
    }
    func length() -> socklen_t {
        return socklen_t(sizeofValue(self))
    }
}

//IPV4 socket struct enhancement
extension sockaddr_in : SockaddrAdditions
{
    internal init(port:UInt16)
    {
        self.init()
        memset(&self, 0, Int(sizeof(sockaddr_in)));//TODO:not very swifty
        sin_family = sa_family_t(AF_INET)
        sin_port = port.bigEndian
        sin_addr.s_addr = UInt32(0x00000000)    // INADDR_ANY = (u_int32_t)0x00000000 ----- <netinet/in.h>
    }
}

//UNIX socket struct enhancement
extension sockaddr_un : SockaddrAdditions
{
    internal init(socketName:String)
    {
        self.init()
        #if !os(Linux)
            sun_len = __uint8_t(sizeof(sockaddr_un))
        #endif
        sun_family = sa_family_t(AF_UNIX);
        
        socketName.withCString {socketPathCharArray in
            withUnsafeMutablePointer(&self.sun_path) {
                memset($0, 0, sizeof(SunPathType))
                memcpy($0, socketPathCharArray, Int(strlen(socketPathCharArray)))
            }
        }
    }
    func length() -> socklen_t
    {
        let mirror = Mirror(reflecting: self.sun_path)
        var countChar = 0
        for child in mirror.children {
            if let val:Int8 = child.value as? Int8 {
                if (val == 0) {
                    break
                }
                countChar += 1
            } else {
                break
            }
            
        }
        return socklen_t((sizeofValue(self) - Int(mirror.children.count)) + countChar)
    }
}

//a base class for a socket-based server (unix sockets, IPV4, IPV6)
public class SocketServer
{
    private let SocketBacklog:Int32 = 5
    
    public weak var delegate:SocketServerDelegate?
    
    private var serverSocketAddr:SockaddrAdditions
    
    private init(socket:SockaddrAdditions)
    {
        serverSocketAddr = socket
    }

    internal func start(delegate:SocketServerDelegate?) -> Bool
    {
        self.delegate = delegate
        
        let serverSocket:SocketDescriptorType = startServer()
        
        if serverSocket == SocketError {
            return false
        }
        
        acceptAndReceive(serverSocket)
        
        return true
    }
    
    private func startServer() -> SocketDescriptorType
    {
        #if os(Linux)
            let SockStream = Int32(SOCK_STREAM.rawValue)
        #else
            let SockStream = SOCK_STREAM
        #endif
        var socketAddr: sockaddr = serverSocketAddr.toSockaddr()
        //socket
        let protocolFamily:Int32 = Int32(socketAddr.sa_family)
        let serverSocket:SocketDescriptorType = socket(protocolFamily, SockStream, 0)
        if serverSocket == SocketError {
            print("error \(errno) while socket")
            return SocketError
        }
        //bind
        if (SocketError == withUnsafePointer(&socketAddr,
              { bind(serverSocket, UnsafePointer($0), serverSocketAddr.length()) }))
        {
            close(serverSocket)
            print("error \(errno) while bind")
            return SocketError
        }
        
        //listen
        if (SocketError == listen(serverSocket, SocketBacklog)) {
            close(serverSocket)
            print("error \(errno) while listen")
            return SocketError
        }
        return serverSocket
    }
    
    private func acceptAndReceive(serverSocket:SocketDescriptorType)
    {
        //set signal
        //#TODO SIGUSR1 on linux
        //setSignal(SIGUSR1, signalHandler: {signal in shutdownAsked = 1});
        
        while shutdownAsked == 0
        {
            var client_addr: sockaddr_un = sockaddr_un()
            var client_addr_size = client_addr.length()
            
            let clientSocket:SocketDescriptorType = withUnsafeMutablePointers(&client_addr, &client_addr_size) {
                accept(serverSocket, UnsafeMutablePointer($0), UnsafeMutablePointer($1))
            }
            
            if clientSocket == SocketError {
                if EINTR == errno && shutdownAsked == 1 {
                    print("signal received")
                    continue
                } else {
                    print("error \(errno) while accept")
                    break
                }
            }
            
            if let delegate = self.delegate {
                let connectedClient = ConnectedClient(socketDescriptor: clientSocket)
                delegate.didAcceptClient(connectedClient)
                connectedClient.waitForData(ReadTimeoutInSec)
                {
                    [unowned self] in
                    if let delegate = self.delegate { //get current value of delegate
                        delegate.didDisconnectClient(connectedClient)
                    }
                }
            }
        }
    }
    
    private func setSignal(aSignal:Int32, signalHandler:(UInt)->Void)
    {
        #if os(Linux)
            var action:sigaction = sigaction()
            var oldaction:sigaction = sigaction()
            action.__sigaction_handler.sa_handler = { signall in shutdownAsked = 1 }
        #else
            var action:sigaction = sigaction()
            var oldaction:sigaction = sigaction()
            action.__sigaction_u = __sigaction_u(__sa_handler:  { signall in shutdownAsked = 1 })
        #endif
        
        sigemptyset(&action.sa_mask)
        sigaction(aSignal, &action, &oldaction)
    
    }

    
    /*
    func setSignal(aSignal:UInt, signalHandler:(UInt) -> Void) -> dispatch_source_t
    {
        #if os(Linux)
            let theSignal = aSignal
        #else
            let theSignal = Int32(aSignal)
        #endif
        let source:dispatch_source_t = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, UInt(theSignal), 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))
        signal(theSignal, SIG_IGN)
        
        dispatch_source_set_event_handler(source, {
            signalHandler(UInt(theSignal))
        });
        dispatch_resume(source);
        return source
    }*/
}

//Unix server
public class UnixSocketServer : SocketServer
{
    var serverAddr:sockaddr_un
    
    init(socketName:String)
    {
        serverAddr = sockaddr_un(socketName: socketName)
        super.init(socket:serverAddr)
    }
    
    override func startServer() -> SocketDescriptorType
    {
        //unlink
        let unlinkResult:SocketReturnType = withUnsafePointer(&serverAddr.sun_path, {unlink(UnsafePointer<Int8>($0))})
        
        if (SocketError == unlinkResult) {
            let error = errno
            if (error != ENOENT) {
                print("error \(errno) while unlink")
                return SocketError
            }
        }
        return super.startServer()
    }
}

//IPV4 Server
public class IPV4SocketServer : SocketServer
{
    init(port:Int)
    {
        let serverAddr = sockaddr_in(port:UInt16(port))
        super.init(socket:serverAddr)
    }
}

//A client
public class ConnectedClient
{
    public var delegate:ConnectedClientDelegate?
    
    public var connected:Bool = false {
        didSet {
            if connected == false {
                if let delegate = self.delegate {
                    delegate.didDisconnect(self)
                }
            }
        }
    }
    
    //MARK:send methods
    public func sendData(data:[UInt8])
    {
        write(socketDescriptor, data, data.count)
    }
    
    public func sendData(data:UnsafePointer<Int8>, count:UInt)
    {
        write(socketDescriptor, data, Int(count))
    }
    
    public func sendString(data:String)
    {
        data.withCString({
            bytes in
            write(socketDescriptor, bytes, Int(strlen(bytes)))
        })
    }
    

    //MARK:Connections
    public func disconnect()
    {
        self.cancelWaitForData()
    }

    //MARK:private (to this file) stuff
    private let socketDescriptor:SocketDescriptorType
    private init(socketDescriptor:SocketDescriptorType)
    {
        self.connected = true
        self.socketDescriptor = socketDescriptor
    }
    
    private func waitWithTimeout(timeoutms:Int) -> SocketReturnType
    {
        #if os(Linux)
            typealias MicroSeconds = Int
        #else
            typealias MicroSeconds = Int32
        #endif
        let numOfFd:Int32 = socketDescriptor + 1
        var readSet:fd_set = fd_set()
        var timeout:timeval = timeval(tv_sec: Int(timeoutms/1000), tv_usec: MicroSeconds(timeoutms - 1000*Int(timeoutms/1000)))
        
        fdZero(&readSet)
        fdSet(socketDescriptor, set: &readSet)
        return select(numOfFd, &readSet, nil, nil, &timeout)
    }
    
    private func waitForData(timeoutInSec:Float, disconnected:() -> Void)
    {
        let queue = dispatch_get_global_queue(Int(DISPATCH_QUEUE_PRIORITY_HIGH), 0)
        my_dispatch_async(queue)
        {
            //read data received
            var readResult = 0
            let READ_BUFFER_SIZE = 1024
            var receiveBuffer = [UInt8](count: READ_BUFFER_SIZE, repeatedValue: 0)
            receiveBuffer.reserveCapacity(READ_BUFFER_SIZE)
            
            repeat {
                let TimeoutResult:Int32 = 0
                let status = self.waitWithTimeout(Int(timeoutInSec*1000))
                
                if status == TimeoutResult {
                    continue
                }
                
                if status == SocketError {
                    if (errno != EBADF) {
                        print("error \(errno) while select")}
                    break
                }
                
                readResult = read(self.socketDescriptor, &receiveBuffer, Int(READ_BUFFER_SIZE))
                if readResult == -1 && errno != EAGAIN && errno != EINTR {
                    print("error \(errno) while read")
                }
                if (readResult > 0) {
                    if let delegate = self.delegate {
                        let range = Range(start:readResult, end:READ_BUFFER_SIZE)
                        receiveBuffer.removeRange(range)
                        delegate.didReceiveData(self, buffer:receiveBuffer)
                    }
                }
            }
            while self.connected
            
            if self.connected {
                close(self.socketDescriptor)
                self.connected = false
            }
            disconnected()
        }
    }
    
    private func cancelWaitForData()
    {
        if self.connected {
            close(self.socketDescriptor)
            self.connected = false
        }
    }
    
    /*
    //future implemen. when GCD linux get dispatch_source
    var source:dispatch_source_t?
    func waitForData(timeoutInSec:Float)
    {
        let queue = dispatch_get_global_queue(Int(DISPATCH_QUEUE_PRIORITY_HIGH), 0)
        let source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socketDescriptor), 0, queue)
        if source != nil {
            self.source = source
            dispatch_source_set_cancel_handler(source) {
                close(self.socketDescriptor)
                self.connected = false
            }
            my_dispatch_source_set_event_handler(source) {
                var readResult = 0
                let READ_BUFFER_SIZE = 1024
                var receiveBuffer = [UInt8](count: READ_BUFFER_SIZE, repeatedValue: 0)
                receiveBuffer.reserveCapacity(READ_BUFFER_SIZE)
                
                readResult = read(self.socketDescriptor, &receiveBuffer, Int(READ_BUFFER_SIZE))
                if readResult == -1 && errno != EAGAIN && errno != EINTR {
                    print("error \(errno) while read")
                    dispatch_source_cancel(source);
                }
                else if (readResult > 0) {
                    if let delegate = self.delegate {
                        let range = Range(start:readResult, end:READ_BUFFER_SIZE)
                        receiveBuffer.removeRange(range)
                        delegate.didReceiveData(self, buffer:receiveBuffer)
                    }
                }
            }
            
            my_dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(timeoutInSec * Float(NSEC_PER_SEC))), queue) { 
                [weak self] in
                if (self != nil) {
                    self!.cancelWaitForData()
                }
            }
            
            dispatch_resume(source);
        }
    }
    
    func cancelWaitForData()
    {
        if let source = self.source {
            dispatch_source_cancel(source)
        }
    }*/
    
    deinit
    {
        //print("ConnectedClient deinit")
    }
    
}
