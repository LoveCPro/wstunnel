#!/usr/bin/lua

local ev = require "ev"
local uwsc = require "uwsc"
local http = require "socket.http"
local ltn12 = require 'ltn12'


local loop = ev.Loop.default

local url
local token
local server = "http://localhost"
--local url = "ws://localhost:8080/_tunnel"

local PING_INTERVAL = 2
local RECONNECT_INTERVAL = 5

local auto_reconnect = true
local do_connect = nil


local function on_open()
	print(loop:now(), "ws tunnel connected")

end

local function start_reconnect()
	if not auto_reconnect then
		loop:unloop()
		return
	end

	ev.Timer.new(function()
		do_connect()
	end, RECONNECT_INTERVAL):start(loop)
end


function getTabBySplitString(str)
	local num
	local method
	local uri
	local reqstbody
	local headerstr
        local subStrTab = {}

        if (str == "" or not str) then
                return
        end
	local splitstr = '\r\n'

	-- get method and uri
        pos = string.find(str, splitstr)
	if (not pos) then
		return
	end
	--get id method uri
	local methodstr = string.sub(str, 1, pos-1)
	num, method = string.match(methodstr, "(%x+)(%a+)")
	local methodpos = string.find(methodstr, method)
	if methodpos then
		local tmppos = string.find(methodstr, "HTTP")
		uri = string.sub(methodstr, methodpos + string.len(method) + 1, tmppos -2)
	else
		print(loop:now(), "req string err")
		return
	end

    str = str.sub(str, pos+2, string.len(str))
	--get request  body
	local bodypos = string.find(str, "\r\n\r\n")
	if (bodypos + 3) == string.len(str) then
		reqstbody = nil
	else
		reqstbody = string.sub(str, bodypos + 4, string.len(str))
	end

	--get header
	headerstr = string.sub(str, 1, bodypos - 1)
	while(true) do
	        pos = string.find(headerstr, splitstr)
		if (not pos) then
                	--最后一行
                  	pos = string.find(headerstr, ":")
			local prestr = string.sub(headerstr, 1, pos - 1)
			local suffix = string.sub(headerstr, pos + 2, string.len(headerstr) +1)
			subStrTab[prestr] = suffix
                    	break
                end

		local subStr = string.sub(headerstr, 1, pos-1)
                local sonpos = string.find(subStr, ":")
                if (not sonpos) then
			break
                end

      	  	local preStr = string.sub(subStr, 1, sonpos - 1)
        	local suffixStr = string.sub(subStr, sonpos + 2, string.len(subStr))
                subStrTab[preStr] = suffixStr

                headerstr = str.sub(headerstr, pos+2, string.len(headerstr))
        end

	return num, method, uri, subStrTab, reqstbody
end

--send req to httpserver and read respons write to ws
local function finishRequst(cl, data)
	local res, code, response_headers, status

	--parse reqdata
	local reqid,  reqmethod, requri, reqheadtab, reqbody = getTabBySplitString(data)
	print(loop:now(), "reqid:", reqid, "method:", reqmethod, "requri:", requri)
	print("reqhead:")
	for k, v in pairs(reqheadtab) do
		print(k, v)
	end
	print("reqbody:", reqbody, "\n")

	--send request to http server
	local response_body = {}
	urltmp = server .. requri

	if reqbody then
	 	res, code, response_headers, status= http.request{
      	    		url = urltmp,
            		method = reqmethod,
           		    headers = reqheadtab,
			        source = ltn12.source.string(reqbody),
      			    sink = ltn12.sink.table(response_body),
 	 	}
	else
	 	res, code, response_headers, status= http.request{
      	    		url = urltmp,
            		method = reqmethod,
           		headers = reqheadtab,
      			sink = ltn12.sink.table(response_body),
 	 	}
	end

	if (not status) then
		return
	end

	--concact  response
	local response = string.format("%s%s\r\n", reqid, status)

    for k, v in pairs(response_headers) do
		response = string.format("%s%s: %s\r\n", response, k, v)
    end

	response = response .. "\r\n"
	if next(response_body) ~= nil  then
		if response_headers["transfer-encoding"] ~= "chunked" then
			response = string.format("%s%s\r\n\r\n", response, table.concat(response_body))
		else
			response = string.format("%s%x\r\n%s\r\n0\r\n\r\n", response, #table.concat(response_body), table.concat(response_body))
		end
	end

	print(loop:now(), "resp:", response)

	--send http response to wstunnel
	cl:send_binary(response)
	response_body = nil
	response = nil
end


do_connect = function()
	local cl, err
	if token then
		local originstr = string.format("Origin: %s\r\n", token)
		local headtab = {["extra_header"] = originstr}
		cl, err = uwsc.new(url, PING_INTERVAL, headtab)
	else
		cl, err = uwsc.new(url, PING_INTERVAL)
	end

	if (not cl) then
	    print(loop:now(), err)
	    return
	end

	cl:on("open", function()
		on_open()
	end)

	cl:on("message", function(data, is_binary)
		--接收到ws server的消息
		print(loop:now(), "Received message:\n", data, "is binary:", is_binary)

		--headle request
		if is_binary then
			finishRequst(cl, data)
		end
	end)

	cl:on("close", function(code, reason)
		print(loop:now(), "Closed by peer:", code, reason)
		cl=nil
		start_reconnect()
	end)

	cl:on("error", function(err, msg)
		print(loop:now(), "Error occurred:", err, msg)
		cl =nil
		start_reconnect()
	end)

end


main = function()
	for key, val in pairs(arg) do
		if (val ==  "-u") then
			url = arg[key + 1]
		elseif (val == "-t") then
			token = arg[key + 1]
		elseif (val == "-s") then
			server = arg[key + 1]
		end
	end

	if (not url) or (not token) then
		local tmpstr = string.format("Usage: %s[option]", arg[0])
		print(tmpstr)
		print("\t-u url\t\t# ws://localhost:8080/_tunnel")
		print("\t-t token\t# rendez-vous token identifying this server")
		print("\t-s server\t# local HTTP(S) server to send received requests")
		return
	end

	ev.Signal.new(function()
		loop:unloop()
	end, ev.SIGINT):start(loop)

	do_connect()

	-- major minor patch
	local version = string.format("%d.%d.%d",  uwsc.version())
	print(loop:now(), "Version:", version)

	loop:loop()
	print(loop:now(), "Normal quit")

end

main()
