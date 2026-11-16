-- emoji 候选推迟到第二页：第一页只放文字候选，emoji 从第 page_size+1 位开始出现。
-- 在 engine/filters 增加 - lua_filter@*emoji_defer_filter（必须放在 simplifier@emoji 之后）
--
-- 识别方式：simplifier 生成的候选类型是 simplified，emoji 的文字里没有字母、数字、汉字、假名、谚文。
-- 简繁转换（traditionalize）出来的候选类型也是 simplified，但含汉字，不会被当成 emoji。
-- 默认按文字样式显示的单个表情补 U+FE0F（见 TEXT_DEFAULT）。
-- 前 page_size 个非 emoji 候选放出之后，被扣住的 emoji 紧接着放出，之后的 emoji 保持原位置；
-- 候选不足一页时，emoji 放在最后。整个过程保持惰性，不会取尽候选。

local M = {}

local function is_emoji_text(text)
    if not text or text == "" then return false end
    local ok, res = pcall(function()
        for _, cp in utf8.codes(text) do
            if (cp >= 0x30 and cp <= 0x39) or (cp >= 0x41 and cp <= 0x5A) or (cp >= 0x61 and cp <= 0x7A)
               or (cp >= 0x3040 and cp <= 0x30FF)     -- 假名
               or (cp >= 0x3400 and cp <= 0x9FFF)     -- 汉字
               or (cp >= 0xF900 and cp <= 0xFAFF)     -- 兼容汉字
               or (cp >= 0xAC00 and cp <= 0xD7AF)     -- 谚文
               or (cp >= 0x20000 and cp <= 0x2FFFF) then  -- 扩展汉字
                return false
            end
        end
        return true
    end)
    return ok and res
end
M.is_emoji_text = is_emoji_text

-- 默认按文字样式显示的表情（Unicode 属性 Emoji = Yes 且 Emoji_Presentation = No，如 ☝ ☹ ✌ ❤），单独出现时
-- 画成黑白线条。emoji 候选只有这样一个码位时补上 U+FE0F，候选里和上屏后都显示成彩色表情。
-- 区间由 Swift 的 Unicode.Scalar.Properties（isEmoji、isEmojiPresentation）生成，排除 ASCII 的数字、# 与 *。
-- 共 207 个码位，116 段
local TEXT_DEFAULT = { {0xA9, 0xA9}, {0xAE, 0xAE}, {0x203C, 0x203C}, {0x2049, 0x2049}, {0x2122, 0x2122}, {0x2139, 0x2139}, {0x2194, 0x2199}, {0x21A9, 0x21AA}, {0x2328, 0x2328}, {0x23CF, 0x23CF}, {0x23ED, 0x23EF}, {0x23F1, 0x23F2}, {0x23F8, 0x23FA}, {0x24C2, 0x24C2}, {0x25AA, 0x25AB}, {0x25B6, 0x25B6}, {0x25C0, 0x25C0}, {0x25FB, 0x25FC}, {0x2600, 0x2604}, {0x260E, 0x260E}, {0x2611, 0x2611}, {0x2618, 0x2618}, {0x261D, 0x261D}, {0x2620, 0x2620}, {0x2622, 0x2623}, {0x2626, 0x2626}, {0x262A, 0x262A}, {0x262E, 0x262F}, {0x2638, 0x263A}, {0x2640, 0x2640}, {0x2642, 0x2642}, {0x265F, 0x2660}, {0x2663, 0x2663}, {0x2665, 0x2666}, {0x2668, 0x2668}, {0x267B, 0x267B}, {0x267E, 0x267E}, {0x2692, 0x2692}, {0x2694, 0x2697}, {0x2699, 0x2699}, {0x269B, 0x269C}, {0x26A0, 0x26A0}, {0x26A7, 0x26A7}, {0x26B0, 0x26B1}, {0x26C8, 0x26C8}, {0x26CF, 0x26CF}, {0x26D1, 0x26D1}, {0x26D3, 0x26D3}, {0x26E9, 0x26E9}, {0x26F0, 0x26F1}, {0x26F4, 0x26F4}, {0x26F7, 0x26F9}, {0x2702, 0x2702}, {0x2708, 0x2709}, {0x270C, 0x270D}, {0x270F, 0x270F}, {0x2712, 0x2712}, {0x2714, 0x2714}, {0x2716, 0x2716}, {0x271D, 0x271D}, {0x2721, 0x2721}, {0x2733, 0x2734}, {0x2744, 0x2744}, {0x2747, 0x2747}, {0x2763, 0x2764}, {0x27A1, 0x27A1}, {0x2934, 0x2935}, {0x2B05, 0x2B07}, {0x3030, 0x3030}, {0x303D, 0x303D}, {0x3297, 0x3297}, {0x3299, 0x3299}, {0x1F170, 0x1F171}, {0x1F17E, 0x1F17F}, {0x1F202, 0x1F202}, {0x1F237, 0x1F237}, {0x1F321, 0x1F321}, {0x1F324, 0x1F32C}, {0x1F336, 0x1F336}, {0x1F37D, 0x1F37D}, {0x1F396, 0x1F397}, {0x1F399, 0x1F39B}, {0x1F39E, 0x1F39F}, {0x1F3CB, 0x1F3CE}, {0x1F3D4, 0x1F3DF}, {0x1F3F3, 0x1F3F3}, {0x1F3F5, 0x1F3F5}, {0x1F3F7, 0x1F3F7}, {0x1F43F, 0x1F43F}, {0x1F441, 0x1F441}, {0x1F4FD, 0x1F4FD}, {0x1F549, 0x1F54A}, {0x1F56F, 0x1F570}, {0x1F573, 0x1F579}, {0x1F587, 0x1F587}, {0x1F58A, 0x1F58D}, {0x1F590, 0x1F590}, {0x1F5A5, 0x1F5A5}, {0x1F5A8, 0x1F5A8}, {0x1F5B1, 0x1F5B2}, {0x1F5BC, 0x1F5BC}, {0x1F5C2, 0x1F5C4}, {0x1F5D1, 0x1F5D3}, {0x1F5DC, 0x1F5DE}, {0x1F5E1, 0x1F5E1}, {0x1F5E3, 0x1F5E3}, {0x1F5E8, 0x1F5E8}, {0x1F5EF, 0x1F5EF}, {0x1F5F3, 0x1F5F3}, {0x1F5FA, 0x1F5FA}, {0x1F6CB, 0x1F6CB}, {0x1F6CD, 0x1F6CF}, {0x1F6E0, 0x1F6E5}, {0x1F6E9, 0x1F6E9}, {0x1F6F0, 0x1F6F0}, {0x1F6F3, 0x1F6F3} }
local function text_default(cp)
    local a, b = 1, #TEXT_DEFAULT
    while a <= b do
        local m = (a + b) // 2
        local r = TEXT_DEFAULT[m]
        if cp < r[1] then b = m - 1 elseif cp > r[2] then a = m + 1 else return true end
    end
    return false
end

local function present(cand)
    local text = cand.text
    local ok, n = pcall(utf8.len, text)
    if not ok or n ~= 1 then return cand end
    if not text_default(utf8.codepoint(text)) then return cand end
    local ok2, sc = pcall(ShadowCandidate, cand, cand.type, text .. "\u{FE0F}", cand.comment)
    return (ok2 and sc) or cand
end
M.present = present

function M.init(env)
    local size = nil
    pcall(function() size = env.engine.schema.page_size end)
    if type(size) ~= "number" or size < 1 then
        pcall(function() size = env.engine.schema.config:get_int("menu/page_size") end)
    end
    M.page_size = (type(size) == "number" and size >= 1) and size or 5
end

-- 自定义表情（emoji_custom.lua）：不推迟，拼音键的放在首位后面，词键的紧跟在对应的词后面；
-- 词典给出的同一个表情（不计 U+FE0F）不再重复出现
local okec, ec = pcall(require, "emoji_custom")
local function norm(t) return (t:gsub("\u{FE0F}", "")) end

local function custom_cand(ref, e)
    local ok, c = pcall(Candidate, "emoji_custom", ref._start, ref._end, e, "")
    if not ok or not c then return nil end
    return present(c)
end

function M.func(input, env)
    local quota = M.page_size or 5
    local held, normal, released = {}, 0, false
    local custom_on = okec and pcall(ec.refresh) and ec.count() > 0
    local code_list = nil
    if custom_on then
        local ok, inp = pcall(function() return env.engine.context.input end)
        code_list = ok and ec.for_code(inp) or nil
    end
    local shown, first = {}, true

    local function emit(cand)   -- 放出一个候选；是文字候选时，后面跟上它关联的自定义表情
        yield(cand)
        if not custom_on or cand.type == "simplified" then return end
        local list = {}
        if first and code_list then for _, e in ipairs(code_list) do list[#list + 1] = e end end
        first = false
        local w = ec.for_word(cand.text)
        if w then for _, e in ipairs(w) do list[#list + 1] = e end end
        for _, e in ipairs(list) do
            local k = norm(e)
            if not shown[k] then
                local c = custom_cand(cand, e)
                if c then shown[k] = true; yield(c) end
            end
        end
    end
    local function release()
        for _, e in ipairs(held) do if not shown[norm(e.text)] then yield(e) end end
        held = {}
    end

    for cand in input:iter() do
        local emoji = cand.type == "simplified" and is_emoji_text(cand.text)
        if emoji then cand = present(cand) end
        if emoji and shown[norm(cand.text)] then
            -- 已作为自定义表情放出过
        elseif not released and emoji then
            held[#held + 1] = cand
        else
            emit(cand)
            normal = normal + 1
            if not released and normal >= quota then
                release()
                released = true
            end
        end
    end
    release()
end

return M
