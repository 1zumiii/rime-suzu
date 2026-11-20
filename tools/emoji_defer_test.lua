-- emoji_defer_filter 的单元测试（模拟 Rime 环境）。
-- 用法：lua tools/emoji_defer_test.lua <仓库根目录>
local repo = arg[1] or "."
package.path = repo .. "/lua/?.lua;" .. package.path

local out
function yield(c) out[#out + 1] = c end

local M = require("emoji_defer_filter")
local fails = 0
local function check(name, cond, extra)
  print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  [" .. extra .. "]") or ""))
  if not cond then fails = fails + 1 end
end

local function word(t) return { text = t, type = "phrase" } end
local function emoji(t) return { text = t, type = "simplified" } end
local function trad(t) return { text = t, type = "simplified" } end   -- 繁体转换结果，类型也是 simplified

-- 惰性迭代器：记录一共被取走多少个候选
local function run(list, page_size)
  local idx = 0
  local input = { iter = function() return function() idx = idx + 1; return list[idx] end end }
  M.init({ engine = { schema = { page_size = page_size } } })
  out = {}
  M.func(input, {})
  local t = {}
  for i, c in ipairs(out) do t[i] = c.text end
  return table.concat(t, " "), idx
end

-- 1. emoji 在第 2 位 → 推迟到第 6 位
local r = run({ word("笑"), emoji("😄"), word("哈"), word("嘻"), word("呵"), word("嘿"), word("哟") }, 5)
check("emoji moved to start of page 2", r == "笑 哈 嘻 呵 嘿 😄 哟", r)

-- 2. 第一页之后的 emoji 保持原位
r = run({ word("a"), word("b"), word("c"), word("d"), word("e"), word("f"), emoji("😀"), word("g") }, 5)
check("emoji after page 1 stay in place", r == "a b c d e f 😀 g", r)

-- 3. 多个 emoji 一起推迟，保持相对顺序
r = run({ word("a"), emoji("😀"), emoji("😁"), word("b"), word("c"), word("d"), word("e"), word("f") }, 5)
check("several emoji keep their order", r == "a b c d e 😀 😁 f", r)

-- 4. 候选不足一页：emoji 放最后
r = run({ word("a"), emoji("😀"), word("b") }, 5)
check("short list: emoji at the end", r == "a b 😀", r)

-- 5. 简繁转换的候选（含汉字）不被当成 emoji
r = run({ word("笑"), trad("笑"), word("哈"), word("嘻"), word("呵"), word("嘿") }, 5)
check("traditional-converted candidate not treated as emoji", r == "笑 笑 哈 嘻 呵 嘿", r)

-- 6. 没有 emoji 时原样输出
r = run({ word("a"), word("b"), word("c") }, 5)
check("no emoji: unchanged", r == "a b c", r)

-- 7. 符号类的 emoji（不含字母/汉字）
check("is_emoji_text: symbols", M.is_emoji_text("❤️") and M.is_emoji_text("👍🏻") and M.is_emoji_text("😄"))
check("is_emoji_text: letters/CJK/digits are not emoji",
      not M.is_emoji_text("abc") and not M.is_emoji_text("笑") and not M.is_emoji_text("1😄") and not M.is_emoji_text(""))

-- 8. 惰性：第一页凑满后，后面的候选不会被提前取走（只取到被消费的位置）
do
  local list = {}
  for i = 1, 100 do list[i] = word("w" .. i) end
  list[2] = emoji("😄")
  local idx = 0
  local input = { iter = function() return function() idx = idx + 1; return list[idx] end end }
  M.init({ engine = { schema = { page_size = 5 } } })
  -- 用协程模拟 Rime 只拉取一页（5 个）候选就丢弃协程
  local co = coroutine.create(function() M.func(input, {}) end)
  local got = {}
  function yield(c) got[#got + 1] = c; if #got >= 5 then coroutine.yield() end end
  coroutine.resume(co)
  check("lazy: pulls only about one page from the source", idx <= 8, "pulled " .. idx)
  check("lazy: first page has no emoji", (function() for _, c in ipairs(got) do if c.type == "simplified" then return false end end return true end)())
end

-- 默认按文字样式显示的单个表情补 U+FE0F
function ShadowCandidate(c, ty, text, comment) return { text = text, type = ty, comment = comment, shadow = true } end
function yield(c) out[#out + 1] = c end   -- 第 8 组把 yield 换成了协程版本，这里恢复
do
  local VS = "\u{FE0F}"
  local up, joy, up_tone = "\u{261D}", "\u{1F602}", "\u{261D}\u{1F3FB}"
  local s1 = run({ emoji(up), emoji(joy), emoji(up_tone), word("食指") }, 1)
  local parts = {}
  for x in s1:gmatch("%S+") do parts[#parts + 1] = x end
  local set = {}
  for _, x in ipairs(parts) do set[x] = true end
  check("FE0F: text-default emoji gets U+FE0F", set[up .. VS] == true and not set[up])
  check("FE0F: emoji-presentation emoji unchanged", set[joy] == true and not set[joy .. VS])
  check("FE0F: sequence with skin tone unchanged", set[up_tone] == true)
  check("FE0F: text candidates unchanged", set["食指"] == true)
end

-- 候选映射（emoji_custom.txt）
do
  local dir = os.tmpname(); os.remove(dir); os.execute("mkdir -p '" .. dir .. "'")
  rime_api = { get_user_data_dir = function() return dir end }
  function Candidate(ty, s, e, text, comment) return { text = text, type = ty, _start = s, _end = e, comment = comment } end
  function yield(c) out[#out + 1] = c end
  local ec = require("emoji_custom")
  local function runc(list, inp)
    local idx = 0
    M.init({ engine = { schema = { page_size = 5 } } })
    out = {}
    M.func({ iter = function() return function() idx = idx + 1; return list[idx] end end },
           { engine = { context = { input = inp } } })
    local t = {}
    for k, c in ipairs(out) do t[k] = c.text end
    return t
  end
  local VS, UP, SWEAT = "\u{FE0F}", "\u{261D}", "\u{1F605}"

  ec.refresh(true)
  local t = runc({ word("上"), word("尚"), emoji(UP .. VS) }, "shang")
  check("custom: no file, unchanged", t[1] == "上" and t[2] == "尚" and t[3] == UP .. VS, table.concat(t, " "))

  local f = io.open(dir .. "/emoji_custom.txt", "w")
  f:write("# 测试\nshang\t" .. UP .. "\n尴尬\t" .. SWEAT .. "\n"); f:close(); ec.refresh(true)
  t = runc({ word("上"), word("尚"), word("商"), emoji(UP .. VS) }, "shang")
  check("custom: pinyin key right after first candidate, with U+FE0F", t[2] == UP .. VS, table.concat(t, " "))
  local n = 0
  for _, x in ipairs(t) do if x:gsub(VS, "") == UP then n = n + 1 end end
  check("custom: dictionary duplicate removed", n == 1, tostring(n))
  t = runc({ word("尴尬"), word("干嘎"), word("w3"), word("w4"), word("w5"), emoji(SWEAT) }, "ganga")
  check("custom: word key right after the word", t[1] == "尴尬" and t[2] == SWEAT and #t == 6, table.concat(t, " "))
  t = runc({ word("刚刚"), word("尴尬") }, "gg")
  check("custom: word key also via abbreviation", t[3] == SWEAT, table.concat(t, " "))
  t = runc({ word("上"), word("尚") }, "shan")
  check("custom: other input unaffected", #t == 2, table.concat(t, " "))

  os.remove(dir .. "/emoji_custom.txt"); ec.refresh(true)
  t = runc({ word("上"), word("尚") }, "shang")
  check("custom: file removed, back to normal", #t == 2, table.concat(t, " "))
  os.execute("rm -rf '" .. dir .. "'")
end

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
