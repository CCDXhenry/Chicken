--!strict

local NumberExtension = {}

local function asFinitePositiveNumber(num: unknown): number?
	if num == nil then
		return nil
	end
	if typeof(num) ~= "number" then
		return nil
	end
	if num ~= num or num == math.huge or num == -math.huge then
		return nil
	end
	if num <= 0 then
		return nil
	end
	return num
end

--格式化大数字
function NumberExtension.FormatBigNumber(num: unknown): string
	local n: number? = asFinitePositiveNumber(num)
	if n == nil then
		return "0"
	end
	if n < 1e3 then
		return tostring(math.floor(n * 100) / 100)
	elseif n < 1e6 then
		return math.floor(n / 10) / 100 .. "K"
	elseif n < 1e9 then
		return math.floor(n / 1e4) / 100 .. "M"
	elseif n < 1e12 then
		return math.floor(n / 1e7) / 100 .. "B"
	elseif n < 1e15 then
		return math.floor(n / 1e10) / 100 .. "T"
	elseif n < 1e18 then
		return math.floor(n / 1e13) / 100 .. "Q"
	elseif n < 1e21 then
		return math.floor(n / 1e16) / 100 .. "Qi"
	elseif n < 1e24 then
		return math.floor(n / 1e19) / 100 .. "S"
	elseif n < 1e27 then
		return math.floor(n / 1e22) / 100 .. "Sp"
	elseif n < 1e30 then
		return math.floor(n / 1e25) / 100 .. "O"
	elseif n < 1e33 then
		return math.floor(n / 1e28) / 100 .. "N"
	else
		return math.floor(n / 1e31) / 100 .. "D"
	end
end

local function getAASuffix(index: number): string
	index -= 1
	return string.char(97 + math.floor(index / 26)) .. string.char(97 + (index % 26))
end

local SIG_DIGITS_AA: number = 3

-- 截断至指定位有效数字（不四舍五入），tostring 自然去掉尾随零
local function formatTruncatedSigDigits(value: number): string
	if value <= 0 then
		return "0"
	end
	local log10v: number = math.log10(value)
	if log10v ~= log10v then
		return "0"
	end
	local magnitude: number = math.floor(log10v)
	local decimalPlaces: number = math.max(0, SIG_DIGITS_AA - 1 - magnitude)
	local multiplier: number = 10 ^ decimalPlaces
	local truncated: number = math.floor(value * multiplier + 1e-9) / multiplier
	return tostring(truncated)
end

--格式化大数字（aa格式）
function NumberExtension.FormatBigNumberAA(num: unknown): string
	local n: number? = asFinitePositiveNumber(num)
	if n == nil then
		return "0"
	end
	if n < 1e3 then
		return formatTruncatedSigDigits(n)
	end

	local log10n: number = math.log10(n)
	if log10n ~= log10n then
		return "0"
	end

	local exp: number = math.floor(log10n / 3)
	local scaled: number = n / (1e3 ^ exp)
	local base: string = formatTruncatedSigDigits(scaled)

	local suffixList: { string } = { "K", "M", "B", "T" }
	if exp <= #suffixList then
		local suffix: string = suffixList[exp]
		if suffix == nil then
			return NumberExtension.FormatBigNumber(n)
		end
		return base .. suffix
	end

	-- aa格式从#suffixList后开始
	local aaIndex: number = exp - #suffixList
	return base .. getAASuffix(aaIndex)
end

return NumberExtension
