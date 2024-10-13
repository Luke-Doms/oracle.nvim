local Job = require("plenary.job")
local M = {}

local sys_prompt = [[
Please generate properly formatted code in response to this query. All explanations, clarifications, or additional information should be placed within comments inside the code block. Return valid, executable code.
]]

local api_key = os.getenv("OAI_API_KEY")

M.setup = function()
	print("test")
	vim.api.nvim_set_keymap(
		"n",
		"<leader>o",
		[[:lua require('oracle').get_prompt()<CR>]],
		{ noremap = true, silent = true }
	)
end

local process_response = function(j, return_val)
	if return_val == 0 then
		local lines = {}
		local result = table.concat(j:result(), "\n")
		local result_table = vim.json.decode(result)
		local content = result_table.choices[1].message.content
		print(content)
		for line in content:gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end
		local row, col = unpack(vim.api.nvim_win_get_cursor(0))
		vim.api.nvim_buf_set_lines(0, row, row, false, lines)
	else
		print("POST request failed with error message: " .. return_val)
	end
end

local process_prompt = function(prompt)
	local data = {
		messages = {
			{
				role = "system",
				content = sys_prompt,
			},
			{
				role = "user",
				content = prompt,
			},
		},
		model = "gpt-3.5-turbo",
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
			"-H",
			"Authorization: Bearer " .. api_key,
			"-d",
			vim.json.encode(data),
			"https://api.openai.com/v1/chat/completions",
		},
		on_exit = function(j, return_val)
			vim.schedule(function()
				process_response(j, return_val)
			end)
		end,
	}):sync()
end

M.get_prompt = function()
	local prompt = vim.fn.input("LLM prompt:")
	process_prompt(prompt)
end

return M
