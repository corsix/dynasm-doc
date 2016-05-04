-- Set rootdir to the directory containing this file, and add both it and dynasm to package.path
local rootdir = "./"
do
  local arg = arg
  if arg and arg[0] then
    prefix = arg[0]:match"^(.*[/\\])" or ""
    if prefix then
      rootdir = prefix
      if package then
        package.path = prefix .."?.lua;".. prefix .."../luajit-2.0/dynasm/?.lua;".. package.path
      end
    end
  end
end

-- Strip region comments from C example files, and collect the regions for later
local code_snippets = {}
for _, fname in ipairs{"bf_c.c", "bf_dynasm.c"} do
  local current_snippets = {}
  local in_file = io.open(rootdir .. fname, "rb")
  local out_file = io.open(rootdir .."../".. fname, "wb")
  local lnum = 1
  for line in in_file:lines() do
    local prefix, sec = line:match"^(%s*)// <(.-)>%s*$"
    if sec then
      if sec:sub(1, 1) == "/" then
        sec = sec:sub(2)
        if not current_snippets[sec] then
          error("</".. sec .. "> without prior <".. sec ..">")
        end
        code_snippets[sec].contents = table.concat(current_snippets[sec], "\n")
        current_snippets[sec] = nil
      else
        if code_snippets[sec] then
          error("Duplicate snippet name ".. sec)
        end
        current_snippets[sec] = {}
        code_snippets[sec] = {fname = fname, lnum = lnum, prefix = prefix}
      end
    else
      for sec, s in pairs(current_snippets) do
        local prefix = code_snippets[sec].prefix
        s[#s + 1] = line:sub(1, #prefix) == prefix and line:sub(#prefix + 1) or line
      end
      out_file:write(line, "\n")
      lnum = lnum + 1
    end
  end
  local sec = next(current_snippets)
  if sec then
    error("<".. sec .."> without subsequent </".. sec .. ">")
  end
end
setmetatable(code_snippets, {__index = function(t, k) error("Unknown code region: ".. k) end})

local html_escapes = {
  ["<"] = "&lt;",
  [">"] = "&gt;",
  ["&"] = "&amp;",
}
local template = io.open(rootdir .."template.html", "rb"):read"*a"

function usual_docgen(fname, pre_pass)
  local contents = io.open(rootdir .. fname, "rb"):read"*a"
  if pre_pass then
    contents = pre_pass(contents)
  end
  contents = contents:gsub('(<pre class="listing">)(.-)(</pre>)', function(a, b, c)
    b = code_snippets[b].contents:gsub("[<>&]", html_escapes)
    return a .. b .. c
  end)
  contents = contents:gsub('(<pre class="diff">)(.-)(</pre>)', function(a, b, c)
    b = b:gsub('([+-])(%S*)(%s*)', function(a, b, c)
      local span = '<span class="'.. (a == "+" and "p" or "m") ..'">'
      return code_snippets[b].contents:gsub("[<>&]", html_escapes):gsub("[^\r\n]+", span .."%0</span>")
    end)
    return a .. b .. c
  end)
  contents = contents:gsub("GITHUB_CLONE_URL", "https://github.com/corsix/dynasm-doc.git")
  contents = contents:gsub("(<pre>)($.-)(</pre>)", function(a, b, c)
    return a .. b:gsub("$ ([^\r\n]+)", '<span class="c">%1</span>') .. c
  end)
  if fname ~= "reference.html" then
    contents = contents:gsub("<code>(dasm_[a-z0-9.]+)</code>", '<code><a href="reference.html#%1">%1</a></code>')
    contents = contents:gsub("<code>(%.[a-z]+)</code>", '<code><a href="reference.html#%1">%1</a></code>')
  end
  contents = contents:gsub("#([a-z0-9._]+)", function(s) return "#".. s:gsub("%.", "_") end):gsub('id="(.-)"', function(s) return 'id="'.. s:gsub("%.", "_") ..'"' end)
  local nav = {}
  local prev_lev = ""
  for lev, id, title in contents:gmatch'<h([23]) id="(.-)">(.-)</h' do
    title = title:gsub("<.->", ""):gsub(" Labels", "")
    if lev == "2" then
      if prev_lev == "3" then
        nav[#nav + 1] = '              </ul>'
      end
      if prev_lev ~= "" then
        nav[#nav + 1] = '            </li>'
      end
      nav[#nav + 1] = '            <li>'
      nav[#nav + 1] = '              <a href="#'.. id ..'">'.. title ..'</a>'
    else
      if prev_lev == "2" then
        nav[#nav + 1] = '              <ul class="nav">'
      end
      nav[#nav + 1] = '                <li><a href="#'.. id ..'">'.. title ..'</a></li>'
    end
    prev_lev = lev
  end
  if prev_lev == "3" then
    nav[#nav + 1] = '              </ul>'
  end
  nav[#nav + 1] = '            </li>'
  nav = table.concat(nav, "\n")
  contents = template:gsub('<li>(<a href="(.-)">)', function(a, href) if href == fname then return '<li class="active">'.. a end end):gsub("NAV", nav):gsub("CONTENTS", (contents:gsub("%%", "%%%%")))
  io.open(rootdir .."../".. fname, "wb"):write(contents)
end

usual_docgen("index.html")
usual_docgen("tutorial.html")
usual_docgen("reference.html")
usual_docgen("instructions.html", function(contents)
local x86 = require "dasm_x86" .mergemaps({},{})
x64 = true
package.loaded.dasm_x86 = nil
local x64 = require "dasm_x64" .mergemaps({},{})
local ops = {}
do
  local seen = {}
  for _, arch_ops in ipairs{x86, x64} do
    for k in pairs(arch_ops) do
      if not seen[k] then
        seen[k] = true
        ops[#ops + 1] = k
      end
    end
  end
end
table.sort(ops)
local reg0 = {
  [8] = "al",
  [16] = "ax",
  [32] = "eax",
  [64] = "rax",
  [80] = "st0",
  [128] = "xmm0",
  [256] = "ymm0",
}
local szprefix = {
  [8] = "byte ",
  [16] = "word ",
  [32] = "dword ",
  [64] = "qword ",
  [80] = "tword ",
  [128] = "oword ",
  [256] = "yword ",
}
local operands = {
  r = function(sz)
    if sz then
      if sz == 128 then
        return "xmm"
      elseif sz == 256 then
        return "ymm"
      else
        return "r".. sz
      end
    else
      return "reg"
    end
  end,
  R = function(sz)
    if sz then
      return reg0[sz]
    else
      return "(al|ax|eax|rax)"
    end
  end,
  C = function(sz)
    return "cl"
  end,
  m = function(sz)
    if sz then
      if sz == 128 then
        return "xmm/m128"
      elseif sz == 256 then
        return "ymm/m256"
      else
        return "r/m".. sz
      end
    else
      return "r/mNN"
    end
  end,
  f = function(sz)
    return "stx"
  end,
  F = function(sz)
    return "st0"
  end,
  x = function(sz, explicit, sizes)
    if sz then
      local prefix = ""
      if explicit then
        prefix = szprefix[sz] or error("Unknown size prefix for ".. sz)
      end
      return prefix .."m".. sz
    else
      if explicit then
        local prefixes = {}
        if sizes:find"b" then prefixes[#prefixes + 1] = "byte" end
        if sizes:find"w" then prefixes[#prefixes + 1] = "word" end
        if sizes:find"d" then prefixes[#prefixes + 1] = "dword" end
        if sizes:find"d" and sizes:find"q" then prefixes[#prefixes + 1] = "aword" end
        if sizes:find"q" then prefixes[#prefixes + 1] = "qword" end
        if #prefixes == 1 then
          return prefixes[1] .." mem"
        else
          return "(".. table.concat(prefixes, "|") ..") mem"
        end
      else
        return "mem"
      end
    end
  end,
  O = function(sz)
    return "mem"
  end,
  i = function(sz)
    if sz then
      return "imm".. sz
    else
      return "imm32"
    end
  end,
  S = function(sz)
    return "imm8"
  end,
  ["1"] = function(sz)
    return "1"
  end,
  I = function(sz)
    return "imm32"
  end,
  P = function(sz)
    return "P?"
  end,
  J = function(sz)
    return "lbl"
  end,
}
local szbits = {
  b = 8, w = 16, d = 32, q = 64, t = 80, f = "80f", o = 128, y = 256,
}
local function explain(nparam, patt)
  if nparam == 0 then
    return ""
  end
  local ops = patt:sub(1, nparam)
  local sizes, encoding = patt:match("([^:]*):(.*)", nparam + 1)
  local s1 = sizes:sub(1, 1)
  local explicit = false
  if s1 == "1" then
    sizes = sizes:sub(2)
    if not ops:sub(1, 1):find"[rR]" then
      explicit = true
    end
  elseif s1 == "2" then
    sizes = sizes:sub(2)
    if not ops:sub(2, 2):find"[rR]" then
      explicit = true
    end
  elseif s1 == "." then
    assert(sizes == ".")
    sizes = ".."
  elseif s1 == "/" then
    sizes = sizes:sub(2)
  else
    if not ops:find"[rR]" then
      explicit = true
    end
  end
  if sizes == "" then
    sizes = "qdwb"
  end
  local sz
  if #sizes == 1 then
    sz = szbits[sizes] or error("Unknown size ".. sizes)
  end
  return ops:gsub(".", function(c)
    if s1 == "/" then
      sz = szbits[sizes:sub(1, 1)]
      sizes = sizes:sub(2)
      explicit = true
    end
    if c == "i" or c == "I" or c == "S" then
      encoding = encoding:gsub("[oOSUWiIJ]", function(e)
        if e == "S" or e == "U" then
          sz = 8
        elseif e == "W" then
          sz = 16
        end
      end, 1)
    end
    local result = operands[c](sz, explicit, sizes)
    return ", ".. result
  end):sub(3)
end
local function op_overloads(nparam, pattstr, name)
  if not pattstr then
    return {}
  end
  local overloads = {}
  local seen = {}
  local lastencoding
  for patt in pattstr:gmatch"[^|]+" do
    patt = patt:gsub(":(.*)", function(encoding)
      if encoding == "" then
        if lastencoding then
          return ":".. lastencoding
        end
      else
        lastencoding = encoding
      end
      return ":".. encoding
    end)
    local patts
    if patt:find"m" then
      patts = {patt:gsub("m", "r"), (patt:gsub("m", "x"))}
    else
      patts = {patt}
    end
    for i = 1, #patts do
      local a, b, c = patts[i]:match"^([rx])([qdwb])([qdwb]):"
      if a then
        local suffix = patts[i]:sub(4)
        patts[i] = a .. b .. suffix
        patts[#patts + 1] = a .. c .. suffix
      else
        a, b = patts[i]:match"^([rx][rx]+)oy(:.*)"
        if a then
          patts[i] = a .. "o" .. b
          patts[#patts + 1] = a .. "y" .. b
        end
      end
    end
    for _, patt in ipairs(patts) do
      local overload = explain(nparam, patt)
      if not seen[overload] then
        local n = #overloads + 1
        seen[overload] = n
        overloads[n] = overload
      end
    end
  end
  for i = #overloads, 1, -1 do
    local simple = overloads[i]:gsub("%(al|ax|eax|rax%)", "reg"):gsub("r%d%d?", "reg"):gsub("imm8", "imm32"):gsub(", 1", ", imm8"):gsub("%(word", "(byte|word")
    if simple ~= overloads[i] and seen[simple] then
      table.remove(overloads, i)
    end
  end
  return overloads
end
local curr_prefix
local li = {}
local outbuf = {}
local function print(s)
  outbuf[#outbuf + 1] = s
end
for _, op in ipairs(ops) do
  local prefix = op:sub(1,1):upper()
  if prefix ~= "." then
    if prefix ~= curr_prefix then
      curr_prefix = prefix
      print(('<hr>\n<h3 id="%s">%s</h3>\n'):format(prefix, prefix))
      li[#li + 1] = ('<li><a href="#%s">%s</a></li>'):format(prefix, prefix)
    end
    local name, nparam = op:match"^(.+)_([0-9%*])$"
    nparam = tonumber(nparam)
    local overloads
    if name == "mov64" then
      overloads = {"r64, imm64 X64", "(al|ax|eax|rax), mem X64", "mem, (al|ax|eax|rax) X64"}
    else
      overloads = {}
      local o86 = op_overloads(nparam, x86[op], name)
      local o64 = op_overloads(nparam, x64[op], name)
      local s64 = {}
      local s86 = {}
      for _, ovr in ipairs(o64) do
        s64[ovr] = true
      end
      for _, ovr in ipairs(o86) do
        if s64[ovr] then
          overloads[#overloads + 1] = ovr
        end
        s86[ovr] = true
      end
      for _, ovr in ipairs(o86) do
        if not s64[ovr] then
          overloads[#overloads + 1] = ovr .." X86"
        end
      end
      for _, ovr in ipairs(o64) do
        if not s86[ovr] then
          overloads[#overloads + 1] = ovr .." X64"
        end
      end
    end
    local prefix = '<pre id="'.. op ..'">'
    for _, overload in ipairs(overloads) do
      print(prefix)
      prefix = "\n"
      if overload ~= "" and overload:sub(1, 1) ~= " " then
        overload = " ".. overload
      end
      overload = overload:gsub(" (m%d+)", ' <a href="#memory">%1</a>'):gsub(" mem", ' <a href="#memory">mem</a>')
      if name == "mov64" then
        overload = overload:gsub("#memory", "%064")
      end
      overload = overload:gsub("lbl", '<a href="#jump-targets">%0</a>')
      for _, r in ipairs{"reg", "cl", "r%d+", "xmm%d?", "ymm%d?", "st[x0]"} do
        overload = overload:gsub(r, '<a href="#registers">%0</a>')
      end
      print("| ".. name .. overload)
    end
    print("</pre>\n")
  end
end
outbuf = contents .. table.concat(outbuf):gsub("(X[86][64])", function(s) return '<span class="badge">'.. s:lower() ..'</span>' end)
outbuf = outbuf:gsub("imm%d+", '<a href="#immediates">%0</a>')
outbuf = outbuf:gsub("%[lbl%]", '[<a href="#jump-targets">lbl</a>]')
outbuf = outbuf:gsub("(Memory</h3>)(.-)(<hr>)", function(a, b, c) return a .. b:gsub("r%d+", '<a href="#registers">%0</a>') .. c end)
return outbuf
end)
