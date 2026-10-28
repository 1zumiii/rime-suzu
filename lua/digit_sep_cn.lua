-- 数字后的标点接中文时恢复成中文标点
-- librime 的 punctuator/digit_separators：刚上屏的文字以数字结尾时（如“发Beta1”），紧接着的 , . : 先按半角暂存，
-- 方便打 3.14、1,000、12:30；接数字或空格时连同半角符号上屏，再按一次同一个键才恢复中文标点。
-- 这里补一条：暂存着半角分隔符时，下一个键是小写字母（要接着打拼音），就替用户再按一次这个键，
-- 让 punctuator 换回中文映射，字母再照常交给后面的处理器。大写字母多半是英文，保持半角。
-- 位置：engine/processors 里 speller 之前。

local kAccepted, kNoop = 1, 2

local reprs = { [","] = "comma", ["."] = "period", [":"] = "colon" }

local function func(key, env)
    if key:release() or key:ctrl() or key:alt() or key:super() then
        return kNoop
    end
    local ch = key.keycode
    if ch < 0x61 or ch > 0x7a then  -- 只管 a-z
        return kNoop
    end
    local ctx = env.engine.context
    local repr = reprs[ctx.input]
    if not repr or ctx:get_option("ascii_mode") or ctx.composition:empty() then
        return kNoop
    end
    -- 暂存后 librime 会把组合 Forward 一步，末尾多一个空段，所以看第一段（与 librime 的 is_after_digit_separator 一致）
    if not ctx.composition:toSegmentation():get_at(0):has_tag("punct_number") then
        return kNoop
    end
    -- 同一个键再按一次：恢复中文映射并确认；再把字母本身送进引擎，与手动按两次再打拼音相同
    env.engine:process_key(KeyEvent(repr))
    env.engine:process_key(key)
    return kAccepted
end

return func
