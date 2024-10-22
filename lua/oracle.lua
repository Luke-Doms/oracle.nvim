local Job = require("plenary.job")
local M = {}

local write_sys_prompt = [[
You are an AI assistant helping a user to write/better understand their code.
Please generate properly formatted code in response to this query. 
All explanations, clarifications, or additional information should be placed within comments inside the code block. 
Return valid, executable code. 
Only respond with the code the user specifically asks for, omit returning the rest of the surrounding code sent in the request, that is provided solely for context to help you better understand the program.
]]

local comment_sys_prompt = [[
Please provide commentary on the code submitted in response to this query as specified in the following prompt.
]]

local api_key = os.getenv("OAI_API_KEY")

M.setup = function()
	vim.api.nvim_set_keymap("n", "<leader>ow", "<cmd>Write<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("v", "<leader>ow", "<cmd>Write<CR>", { noremap = true, silent = true })

	vim.api.nvim_set_keymap("n", "<leader>od", "<cmd>Dialogue<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("v", "<leader>od", "<cmd>Dialogue<CR>", { noremap = true, silent = true })
end

local write_to_cursor = function(lines)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, lines)
end

local write_to_new_buf = function(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_command("split")
	local window = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(window, buf)
	vim.api.nvim_win_set_height(window, 10)
end

local get_total_text = function()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local total_text = table.concat(lines, "\n")
	return total_text
end

local get_selected_text = function(delete)
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")
	vim.fn.setpos("'<", start_pos)
	vim.fn.setpos("'>", end_pos)
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, start_pos[2] - 1, end_pos[2], false)
	local selected_text = table.concat(lines, "\n")
	if delete then
		vim.api.nvim_buf_set_lines(buf, start_pos[2] - 1, end_pos[2], true, {})
		vim.api.nvim_command("normal! '<")
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
				--vim.api.nvim_echo({ { line, "normal" } }, true, {})
				table.insert(lines, line)
			end
		end
		write_lines(lines)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>", true, false, true), "n", true)
	else
		print("POST request failed with error message: " .. return_val)
	end
end

local process_prompt = function(user_prompt, total_text, selected_text, sys_prompt, write_lines)
	local context = "Here is the total file for context: \n" .. total_text
	local prompt
	if not selected_text then
		prompt = user_prompt
	else
		prompt = "code to rewrite or comment on, ONLY RESPOND IN REFERENCE TO THIS: \n"
			.. selected_text
			.. "\n these are the users instructions, only respond to this in reference to the code sent above: "
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
				content = context,
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
	}):start()
end

--consolodate these functions
M.write_req = function()
	local total_text = get_total_text()
	local mode = vim.fn.mode()
	local selected_text = nil
	if mode == "v" or mode == "V" then
		selected_text = get_selected_text(true)
	end
	local user_prompt = vim.fn.input("LLM write prompt: ")
	process_prompt(user_prompt, total_text, selected_text, write_sys_prompt, write_to_cursor)
end

M.comment_req = function()
	local total_text = get_total_text()
	local mode = vim.fn.mode()
	local selected_text = nil
	if mode == "v" or mode == "V" then
		selected_text = get_selected_text(false)
	end
	local user_prompt = vim.fn.input("LLM dialogue prompt: ")
	process_prompt(user_prompt, total_text, selected_text, comment_sys_prompt, write_to_new_buf)
end

vim.api.nvim_create_user_command("Write", M.write_req, {})
vim.api.nvim_create_user_command("Dialogue", M.comment_req, {})
return M
