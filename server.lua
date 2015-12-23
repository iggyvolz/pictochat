local status,socket=pcall(require,"socket")
if not status then error("Please install luasocket!\n"..socket) end
local status,json=require "json"
if not status then error("Please install luajson!\n"..json) end
local status,settings=pcall(dofile,"settings.lua")
if not status then error("No settings.lua found, or error in settings.lua!\n"..settings) end
VERSION="0.1"
server=assert(socket.bind("*",settings.port))
do
  local tmeta={__index=table}
  function table.new(t)
    t=t or {}
    setmetatable(t,tmeta)
    return t
  end
end
chatroom=table.new{new=function(limit)
  limit=limit
  return table.new{
    users=table.new(), -- Users in room, indexed numerically
    limit=limit,
    msg=function(self,sock,msg)
      for i=1,#self.users do
        self.users[i]:send(json.encode({action="msg",data={msg=msg,from=names[sock]}}))
      end
    end,
    adduser=function(self,sock)
      self.users:insert(sock)
      for i=1,#self.users do
        self.users[i]:send(json.encode({action="adduser",data=names[sock]}))
      end
    end,
    removeuser=function(self,sock)
      self.users:insert(sock)
      for i=1,#self.users do
        self.users[i]:send(json.encode({action="removeuser",data=names[sock]}))
      end
    end
  }
  end
}
chatrooms=table.new()
for i,v in pairs(settings.chats) do
  chatrooms[i]=chatroom.new(v.limit)
end
lobby=table.new() -- Sockets in lobby, indexed numerically
clients=table.new() -- All client sockets, indexed numerically
roomsbyclient=table.new() -- Room that client is in, indexed by client sock
names=table.new() -- User names, indexed by client sock
function welcome()
  local toreturn=table.new({"PictoChat v"..VERSION})
  local chatroomnames=table.new()
  for i in pairs(chatrooms) do
    chatroomnames:insert(i)
  end
  chatroomnames:sort()
  for i,n in pairs(chatroomnames) do
    toreturn:insert(n..": "..#chatrooms[n].users.."/"..chatrooms[n].limit)
  end
  return toreturn:concat("\n")
end
while true do
  do -- Get new clients
    server:settimeout(0)
    local a=server:accept()
    if a then
      lobby:insert(a)
      clients:insert(a)
      a:settimeout(0)
      a:send(welcome().."\n")
    end
  end
  local messages=socket.select(clients,nil,1)
  do -- Check for joins in lobby
    for i=1,#messages do
      if roomsbyclient[messages[i]] then
        while true do
          local rcv=messages[i]:receive()
          if not rcv then break end
          local status,msg=pcall(json.decode,rcv)
          if not status or not msg or not msg.action or not msg.data then
            messages[i]:send(json.encode{action="DAFUQ",data="INVALID_JSON"})
          elseif msg.action == "send" then
            chatrooms[roomsbyclient[messages[i]]]:msg(messages[i],msg.data)
          elseif msg.action == "quit" then
            roomsbyclient[messages[i]]=nil
            chatrooms[msg.data]:removeuser(messages[i])
          elseif msg.action == "debug" then
            require "debug".debug()
          else
            messages[i]:send(json.encode{action="DAFUQ",data="INVALID_ACTION"})
          end
        end
      else
        while true do
          local rcv=messages[i]:receive()
          if not rcv then break end
          local status,msg=pcall(json.decode,rcv)
          if not status or not msg or not msg.action or not msg.data then
            messages[i]:send(json.encode{action="DAFUQ",data="INVALID_JSON"})
          elseif msg.action == "name" then
            names[messages[i]]=msg.data
            messages[i]:send(json.encode{action="nameok",data=msg.data})
          elseif msg.action == "join" then
            if not names[messages[i]] then
              messages[i]:send(json.encode{action="DAFUQ",data="PICK_A_NAME"})
            elseif not chatrooms[msg.data] then
              messages[i]:send(json.encode{action="DAFUQ",data="INVALID_ROOM"})
            elseif chatrooms[msg.data].limit==#chatrooms[msg.data].users then
              messages[i]:send(json.encode{action="DAFUQ",data="ROOM_FULL"})
            else
              roomsbyclient[messages[i]]=msg.data
              chatrooms[msg.data]:adduser(messages[i])
            end
          else
            messages[i]:send(json.encode{action="DAFUQ",data="INVALID_ACTION"})
          end
        end
      end
    end
  end
end
