local Job = require("plenary.job")

local api_key = os.getenv("OAI_API_KEY")

local test_prompt = "write a haiku for me"

local M = {}

M.setup = function()
	print("hello")
end

M.haiku = function()
	print(api_key)
	local data = {
		messages = {
			{
				role = "system",
				content = "proceed normally",
			},
			{
				role = "user",
				content = test_prompt,
			},
		},
		model = "gpt-4o-mini",
		temperature = 0.7,
	}
	Job:new({
		command = "curl",
		args = {
			"-N",
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-d",
			vim.json.encode(data),
			"_H",
			"Authorization: Bearer " .. api_key,
			"https://api.openai.com/v1/chat/completions",
		},
		on_exit = function(j, return_val)
			if return_val == 0 then
				local result = table.concat(j:result(), "\n")
				print("POST request was successful!")
				print("Response: " .. result)
			else
				print("POST request failed with exit code: " .. return_val)
			end
		end,
	}):sync()
end

return M
