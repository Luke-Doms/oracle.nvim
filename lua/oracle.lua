local Job = require("plenary.job")
local M = {}

local write_sys_prompt = [[
Please generate properly formatted code in response to this query. All explanations, clarifications, or additional information should be placed within comments inside the code block. Return valid, executable code.
]]

local comment_sys_prompt = [[
Please provide commentary on the code submitted in response to this query as specified in the following prompt. Make sure when discussing specific lines in the code to reference the corresponding line numbers. The first line in the following code is 
]]

local api_key = os.getenv("OAI_API_KEY")

M.setup = function()
	vim.api.nvim_set_keymap("n", "<leader>ow", "<cmd>Write<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("v", "<leader>ow", "<cmd>Write<CR>", { noremap = true, silent = true })

	vim.api.nvim_set_keymap("v", "<leader>oc", "<cmd>Comment<CR>", { noremap = true, silent = true })
end

local write_to_cursor = function(lines)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	vim.api.nvim_buf_set_lines(0, row, row, false, lines)
end

local write_to_new_buf = function(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_command("split")
	local window = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(window, buf)
	vim.api.nvim_win_set_height(window, 10)
end

local get_selected_text = function(delete)
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	print("this is the start position " .. start_pos[2] .. "this is the end position " .. end_pos[2])
	print(delete)
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
	local selected_text = table.concat(lines, "\n")
	if delete then
		vim.api.nvim_buf_set_lines(buf, start_pos[2] - 2, end_pos[2] + 1, true, {})
	end
	return selected_text
end

local process_response = function(j, return_val, write_lines)
	if return_val == 0 then
		local lines = {}
		local result = table.concat(j:result(), "\n")
		local result_table = vim.json.decode(result)
		local content = result_table.choices[1].message.content
		for line in content:gmatch("[^\r\n]+") do
			--filter out markdown ticks
			if string.sub(line, 1, 3) ~= "```" then
				vim.api.nvim_echo({ { line, "normal" } }, true, {})
				table.insert(lines, line)
			end
		end
		write_lines(lines)
	else
		print("POST request failed with error message: " .. return_val)
	end
end

local process_prompt = function(user_prompt, selected_text, sys_prompt, write_lines)
	local buf = vim.api.nvim_get_current_buf()
	local total_context = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
	local total_content = table.concat(total_context, "\n")

	local prompt
	if not selected_text then
		prompt = total_content .. user_prompt
	else
		prompt = total_content
			.. "\n code to rewrite or comment on: "
			.. selected_text
			.. "\n users instructions: "
			.. user_prompt
	end

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
				process_response(j, return_val, write_lines)
			end)
		end,
	}):sync()
end

M.write_req = function()
	local selected_text = nil
	local mode = vim.fn.mode()
	print(mode)
	if mode == "v" or mode == "V" then
		selected_text = get_selected_text(true)
	end
	local user_prompt = vim.fn.input("LLM write prompt: ")
	process_prompt(user_prompt, selected_text, write_sys_prompt, write_to_cursor)
end

M.comment_req = function()
	local selected_text = get_selected_text(false)
	local user_prompt = vim.fn.input("LLM comment prompt: ")
	process_prompt(user_prompt, selected_text, comment_sys_prompt, write_to_new_buf)
end

vim.api.nvim_create_user_command("Write", M.write_req, {})
vim.api.nvim_create_user_command("Comment", M.comment_req, {})

return M
