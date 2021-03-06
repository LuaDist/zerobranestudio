-- Copyright 2011-12 Paul Kulchenko, ZeroBrane LLC

local gideros
local win = ide.osname == "Windows"
local mac = ide.osname == "Macintosh"

local function exePath()
  local mainpath = ide.editorFilename:gsub("[^/\\]+$","")
  local macExe = mainpath..'bin/lua.app/Contents/MacOS/lua'
  return ide.config.path.lua or
        (ide.osname == "Windows" and mainpath..[[bin\lua.exe]]
     or (ide.osname == "Unix" and [[lua]]) -- using installed lua
     or (wx.wxFileExists(macExe) and macExe or mainpath..[[bin/lua]]))
end

local function isValidPid(bid, cmd)
  if not bid or bid == -1 or bid == 0 then
    DisplayOutputLn(("Program unable to run as '%s'."):format(cmd))
    return
  end
  return bid
end

local function waitToComplete(bid)
  while wx.wxProcess.Exists(bid) do
    wx.wxSafeYield()
    wx.wxWakeUpIdle()
    wx.wxMilliSleep(100)
  end
end

return {
  name = "Gideros",
  description = "Gideros mobile platform",
  api = {"baselib", "gideros"},
  frun = function(self,wfilename,rundebug)
    gideros = gideros or ide.config.path.gideros -- check if the path is configured
    if not gideros then
      local sep = win and ';' or ':'
      local default =
           win and ([[C:\Program Files\Gideros]]..sep..[[D:\Program Files\Gideros]]..sep..
                    [[C:\Program Files (x86)\Gideros]]..sep..[[D:\Program Files (x86)\Gideros]]..sep)
        or mac and ('/Applications/Gideros Studio/Gideros Player.app/Contents/MacOS'..sep)
        or ''
      local path = default
                 ..(os.getenv('PATH') or '')..sep
                 ..(os.getenv('HOME') and os.getenv('HOME') .. '/bin' or '')
      local paths = {}
      for p in path:gmatch("[^"..sep.."]+") do
        gideros = gideros or GetFullPathIfExists(p, win and 'GiderosPlayer.exe' or 'Gideros Player')
        table.insert(paths, p)
      end
      if not gideros then
        DisplayOutputLn("Can't find gideros executable in any of the folders in PATH: "
          ..table.concat(paths, ", "))
        return
      end
    end
    if gideros and not wx.wxFileName(gideros):FileExists() then
      DisplayOutputLn("Can't find the specified gideros executable '"..gideros.."'.")
      return
    end

    local giderostools = wx.wxFileName.DirName(wx.wxFileName(gideros)
      :GetPath(wx.wxPATH_GET_VOLUME)
      ..(win and '/Tools' or '/../../../Gideros Studio.app/Contents/Tools'))
    giderostools:Normalize()
    local giderospath = giderostools:GetPath(wx.wxPATH_GET_VOLUME)
    local gdrbridge = GetFullPathIfExists(giderospath, win and 'gdrbridge.exe' or 'gdrbridge')
    if not gdrbridge then
      DisplayOutputLn("Can't find gideros bridge executable in '"..giderospath.."'.")
      return
    end

    -- find *.gproj file in the project directory
    local file
    for _, proj in ipairs(FileSysGet(self:fworkdir(wfilename).."/*.gproj", wx.wxFILE)) do
      if file then
        DisplayOutputLn("Found multiple .gproj files in the project directory; ignored '"..proj.."'.")
      end
      file = file or proj
    end
    if not file then
      DisplayOutputLn("Can't find gideros project file in the project directory.")
      return
    end

    if rundebug then DebuggerAttachDefault(
      {redirect = "c", runstart = ide.config.debugger.runonstart ~= false}) end

    local pid
    local remote = ide.config.gideros and ide.config.gideros.remote
    if remote then
      local cmd = ('"%s" %s "%s"'):format(gdrbridge, 'setip', remote)
      DisplayOutputLn(("Configuring remote player at %s."):format(remote))
      local bid = wx.wxExecute(cmd, wx.wxEXEC_ASYNC)
      if not isValidPid(bid, cmd) then return end
      waitToComplete(bid) -- wait for a bit to give Gideros chance to connect
    else
      local cmd = ('"%s"'):format(gideros)
      -- CommandLineRun(cmd,wdir,tooutput,nohide,stringcallback,uid,endcallback)
      pid = CommandLineRun(cmd,self:fworkdir(wfilename),not mac,true,nil,nil,
        function() ide.debugger.pid = nil end)
      if not pid then return end
    end

    do
      DisplayOutputLn("Starting the player and waiting for the bridge to connect at '"..gdrbridge.."'.")
      local cmd = ('"%s" %s'):format(gdrbridge, 'isconnected')
      local attempts, connected = 12
      for _ = 1, attempts do
        local proc = wx.wxProcess()
        proc:Redirect()
        proc:Connect(wx.wxEVT_END_PROCESS, function(event) proc = nil end)
        local bid = wx.wxExecute(cmd, wx.wxEXEC_ASYNC + wx.wxEXEC_MAKE_GROUP_LEADER, proc)
        if not isValidPid(bid, cmd) then return end

        local streamin = proc:GetInputStream()
        for _ = 1, 20 do
          if streamin:CanRead() then
            connected = tonumber(streamin:Read(4096)) == 1
            break end
          wx.wxSafeYield()
          wx.wxWakeUpIdle()
          wx.wxMilliSleep(250)
        end

        if connected then break end
        if connected == nil and proc then
          wx.wxProcess.Kill(bid, wx.wxSIGKILL, wx.wxKILL_CHILDREN)
          if not remote then wx.wxProcess.Kill(pid, wx.wxSIGKILL, wx.wxKILL_CHILDREN) end
          DisplayOutputLn("Couldn't connect to the player. Try again or check starting the player and the bridge manually.")
          return
        end
      end
      if not connected then
        if not remote then wx.wxProcess.Kill(pid, wx.wxSIGKILL, wx.wxKILL_CHILDREN) end
        DisplayOutputLn("Couldn't connect after "..attempts.." attempts. Try again or check starting the player manually.")
        return
      end

      local cmd = ('"%s" %s "%s"'):format(gdrbridge, 'play', file)
      DisplayOutputLn(("Starting project file '%s'."):format(file))
      local bid = wx.wxExecute(cmd, wx.wxEXEC_ASYNC)
      if not isValidPid(bid, cmd) then return end
    end
    return pid
  end,
  fprojdir = function(self,wfilename)
    return wfilename:GetPath(wx.wxPATH_GET_VOLUME)
  end,
  fworkdir = function(self,wfilename)
    return ide.config.path.projectdir or wfilename:GetPath(wx.wxPATH_GET_VOLUME)
  end,
  hasdebugger = true,
  fattachdebug = function(self) DebuggerAttachDefault() end,
  scratchextloop = true,
}
