# Depsic

Depsic is a simple Simple CGI framework in Swift. It works on OSX and Linux (Ubuntu 15.10).

Associated with a web server like nginx, it lets you handle http requests with closures:

```swift
let scgi = Depsic()

//Create a SCGI server: (you can add several)
scgi.addServer(IPV4SocketServer(port:10001)) // or on unix socket using UnixSocketServer(socketName:"/tmp/socket")

//Handle a request on url http://<server>/hello.
scgi.forRequest({ (request:RequestInfo) -> Bool in
        return request.uri == "/hello"
    },
    respond: {(request:RequestInfo) throws -> Response<String> in
        return Response<String>(content:"Hello from the other side")
})

//wait for requests (blocking call)
scgi.waitForServers()
```

## nginx configuration ##
####install nginx####

on OSX:

install homebrew if you haven't, then

    brew install nginx

on Linux (Ubuntu):

    sudo apt-get install nginx


####Configure SCGI in nginx config####

In order to serve request on http://localhost:8080, you need to add the following lines to
your nginx config file.

on OSX:

    nano /usr/local/etc/nginx/nginx.conf 

add:

```
    server {
        listen       8080;
        server_name  localhost;
        location / {
           scgi_pass  localhost:10001; 
           #scgi_pass  unix:/tmp/socket; for unix socket
           scgi_param  SCRIPT_FILENAME  /scripts$fastcgi_script_name;
           include scgi_params;
        }
    }
```
on Linux:

Do the same changes to the configuration file in:

    sudo nano /etc/nginx/nginx.conf

## Compilation on Linux ##
### install swift ###
On Linux, you also need to install swift.

The code has been tested with the version from december 10, 2015:

https://swift.org/builds/swift-2.2-branch/ubuntu1510/swift-2.2-SNAPSHOT-2015-12-10-a/swift-2.2-SNAPSHOT-2015-12-10-a-ubuntu15.10.tar.gz

Use the following tutorials:

http://www.makeuseof.com/tag/start-programming-swift-ubuntu/

or

http://www.alwaysrightinstitute.com/swift-on-linux-in-vbox-on-osx/

You will also need libdispatch (aka GCD), follow the tutorial here (section Grand Central Dispatch):
http://www.alwaysrightinstitute.com/swift-on-linux-in-vbox-on-osx/

### Build ###

Get the source code

    git clone http://github.com/depinette/Depsic

Build CDispatch

CDispatch is swift module encapsulation of libdispatch.

    make -C ./Depsic/CDispatch

Build the app

    swift build --chdir ./Depsic/Depsic
 
## Compilation on OSX ##

Use Xcode

## Test ##

Launch nginx

    nginx

Launch the app

    ./Depsic/Depsic/.build/debug/simplecgiapp

Connect with curl

    curl localhost:8080/
    
    
