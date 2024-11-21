local Job = require("plenary.job")
local M = {}

local write_sys_prompt = [[
You are an AI assistant helping a user to write/better understand their code.
Please generate properly formatted code in response to this query. 
All explanations, clarifications, or additional information should be placed within comments inside the code block. 
Return valid, executable code.
Only respond with the code the user specifically asks for, omit returning the rest of the surrounding code sent in the request, that is provided solely for context to help you better understand the program.
]]

local dialouge_sys_prompt = [[
Please provide commentary on the code submitted in response to this query as specified in the following prompt.
]]

local api_key = os.getenv("OAI_API_KEY")
local current_job = nil
local dialouge = {
	buf = nil,
	window = nil,
}
local main = {
	buf = nil,
	window = nil,
}

M.setup = function()
	vim.api.nvim_set_keymap("n", "<leader>ow", "<cmd>Write<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("v", "<leader>ow", "<cmd>Write<CR>", { noremap = true, silent = true })

	vim.api.nvim_set_keymap("n", "<leader>od", "<cmd>Dialogue<CR>", { noremap = true, silent = true })
	vim.api.nvim_set_keymap("v", "<leader>od", "<cmd>Dialogue<CR>", { noremap = true, silent = true })
end

local write_to_cursor = function(data)
	local current_window = vim.api.nvim_get_current_win()
	local cursor_position = vim.api.nvim_win_get_cursor(current_window)
	local row, col = cursor_position[1], cursor_position[2]
	local lines = vim.split(data, "\n")
	vim.api.nvim_put(lines, "c", true, true)
	local num_lines = #lines
	local last_line_length = #lines[num_lines]
	vim.api.nvim_win_set_cursor(current_window, { row + num_lines - 1, col + last_line_length })
end

local get_total_text = function(buf)
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

local process_response = function(res, write_lines)
	local json = res:match("^data: (.+)$")
	if json then
		if json == "[DONE]" then
			return true
		end
		local content = vim.json.decode(json)
		vim.schedule(function()
			local data
			if content.choices and content.choices[1] and content.choices[1].delta then
				data = content.choices[1].delta.content
			end
			if data then
				vim.cmd("undojoin")
				write_lines(data)
			end
		end)
	end
	return false
end

local process_prompt = function(user_prompt, total_text, dialouge_context, selected_text, sys_prompt, write_lines)
	local code_context_prompt = "Here is the total file for context: \n" .. total_text
	local dialouge_context_prompt = "Here is a record of your previous responses to api requests this session, if blank you can ignore this: \n"
		.. dialouge_context
	local user_request
	if not selected_text then
		user_request = user_prompt
	else
		user_request = "code to rewrite or comment on, ONLY RESPOND IN REFERENCE TO THIS: \n"
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
				content = code_context_prompt,
			},
			{
				role = "user",
				content = dialouge_context_prompt,
			},
			{
				role = "user",
				content = user_request,
			},
		},
		model = "gpt-3.5-turbo",
		temperature = 0.7,
		stream = true,
	}

	current_job = Job:new({
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
		on_stdout = function(_, res)
			process_response(res, write_lines)
		end,
		on_exit = function(_, return_val)
			if return_val ~= 0 then
				print("POST request failed with error message: " .. return_val)
			end
			current_job = nil
			vim.schedule(function()
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-c>", true, false, true), "n", true)
			end)
		end,
	})
	vim.api.nvim_command("normal! o")
	current_job:start()
end

--consolodate these functions
M.write_req = function()
	main.buf = vim.api.nvim_get_current_buf()
	local total_text = get_total_text(main.buf)
	local mode = vim.fn.mode()
	local selected_text = nil
	if mode == "v" or mode == "V" then
		selected_text = get_selected_text(true)
	end
	local user_prompt = vim.fn.input("LLM write prompt: ")
	local dialouge_context = ""
	process_prompt(user_prompt, total_text, dialouge_context, selected_text, write_sys_prompt, write_to_cursor)
end

M.dialouge_req = function()
	if dialouge.buf then
		if vim.api.nvim_get_current_buf() ~= dialouge.buf then
			main.buf = vim.api.nvim_get_current_buf()
		end
	else
		dialouge.buf = vim.api.nvim_create_buf(false, true)
		main.buf = vim.api.nvim_get_current_buf()
	end

	local total_text = get_total_text(main.buf)
	local dialouge_context = get_total_text(dialouge.buf)

	if dialouge.window and vim.api.nvim_win_is_valid(dialouge.window) then
		vim.api.nvim_set_current_win(dialouge.window)
	else
		vim.api.nvim_command("split")
		dialouge.window = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(dialouge.window, dialouge.buf)
		vim.api.nvim_win_set_height(dialouge.window, 10)
	end

	local mode = vim.fn.mode()
	local selected_text = nil
	if mode == "v" or mode == "V" then
		selected_text = get_selected_text(false)
	end
	local user_prompt = vim.fn.input("LLM dialogue prompt: ")
	process_prompt(user_prompt, total_text, dialouge_context, selected_text, dialouge_sys_prompt, write_to_cursor)
end

vim.api.nvim_create_user_command("Write", M.write_req, {})
vim.api.nvim_create_user_command("Dialogue", M.dialouge_req, {})

return M
--make dialouge jump to bottom of buffer before printing response, also add an indent and exit visual mode prior to printing
