-- emoji_custom.lua — 自定义表情关联（由 emoji_defer_filter 调用）
-- 文件：用户目录的 emoji_custom.txt，每行“键<Tab>表情”，一个键可以跟多个表情（用空格隔开），# 开头为注释。
--   键是小写字母：输入串（去掉隔音符与空格）恰好等于它时，表情排在首位候选后面。例：shang<Tab>☝️
--   键含其他字符（汉字词等）：候选里出现这个词时，表情紧跟在它后面。例：尴尬<Tab>😅
-- 手机上在设置的“自定义表情”页编辑；电脑上直接编辑文件，几秒内生效，不用重新部署。文件不存在时什么都不做。

local M = {}

local CHECK_SEC = 3
local st = { by_code = {}, by_word = {}, size = -1, checked = nil, n = 0 }

local function path()
    local ok, ud = pcall(function() return rime_api.get_user_data_dir() end)
    if ok and type(ud) == "string" and ud ~= "" then return ud .. "/emoji_custom.txt" end
    return nil
end

local function parse(fh)
    local by_code, by_word, n = {}, {}, 0
    for line in fh:lines() do
        line = line:gsub("\r$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, rest = line:match("^([^\t]+)\t(.+)$")
            if key then
                key = key:gsub("^%s+", ""):gsub("%s+$", "")
                local list = {}
                for e in rest:gmatch("%S+") do list[#list + 1] = e end
                if key ~= "" and #list > 0 then
                    local t = key:match("^[a-z]+$") and by_code or by_word
                    local cur = t[key] or {}
                    for _, e in ipairs(list) do cur[#cur + 1] = e end
                    t[key] = cur
                    n = n + 1
                end
            end
        end
    end
    return by_code, by_word, n
end

function M.refresh(force)
    local now = os.time()
    if not force and st.checked and now - st.checked < CHECK_SEC then return end
    st.checked = now
    local p = path()
    local fh = p and io.open(p, "r")
    if not fh then
        st.by_code, st.by_word, st.n, st.size = {}, {}, 0, -1
        return
    end
    local size = fh:seek("end") or 0
    if size ~= st.size then
        fh:seek("set")
        local ok, a, b, n = pcall(parse, fh)
        if ok then st.by_code, st.by_word, st.n, st.size = a, b, n, size end
    end
    fh:close()
end

function M.count() return st.n end
function M.for_code(input) return st.by_code[(input or ""):gsub("[' ]", "")] end
function M.for_word(text) return st.by_word[text] end

return M
