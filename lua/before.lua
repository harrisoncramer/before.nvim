local M = {}

M.edit_locations = {}
M.dedupe_table = {}
M.cursor = 1
M.max_entries = nil
M.history_wrap_enabled = nil

local function within_bounds(bufnr, line)
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  return line > 0 and line < total_lines + 1
end

local function bufvalid(bufnr)
  return vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_is_valid(bufnr)
end

local function same_line(this_location, that_location)
  return this_location.line == that_location.line and this_location.bufnr == that_location.bufnr
end

local function is_regular_buffer(bufnr)
  return vim.api.nvim_buf_get_option(bufnr, 'buftype') == ''
end

local function should_remove(location)
  return not bufvalid(location.bufnr) or not within_bounds(location.bufnr, location.line) or
      not is_regular_buffer(location.bufnr)
end

local function assign_location(new_location, location_idx, new_cursor)
  local key = string.format("%d;%d", new_location.line, new_location.bufnr)

  local same_line_history_idx = M.dedupe_table[key]
  if same_line_history_idx then
    table.remove(M.edit_locations, same_line_history_idx)
    location_idx = location_idx - 1
    new_cursor = new_cursor - 1
  end

  M.edit_locations[location_idx] = new_location
  M.cursor = new_cursor
  M.dedupe_table[key] = #M.edit_locations
end

function M.track_edit()
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local location = { bufnr = bufnr, line = pos[1], col = pos[2] }

  if is_regular_buffer(bufnr) and within_bounds(location.bufnr, location.line) then
    assign_location(location, #M.edit_locations + 1, #M.edit_locations + 1)
  end

  if #M.edit_locations > M.max_entries then
    table.remove(M.edit_locations, 1)
    M.cursor = M.max_entries
  end
end

local function find_backwards_jump(currentLocation)
  local local_cursor = M.cursor
  local lookback_amount = M.cursor
  for i = 0, lookback_amount do
    local_cursor = local_cursor - i
    local location = M.edit_locations[local_cursor]

    if location and should_remove(location) then
      table.remove(M.edit_locations, local_cursor)
    else
      if location and not same_line(currentLocation, location) then
        M.cursor = local_cursor
        return location
      end
    end
  end

  if M.history_wrap_enabled then
    local fallback_location = M.edit_locations[#M.edit_locations]
    if fallback_location and should_remove(fallback_location) then
      table.remove(M.edit_locations, #M.edit_locations)
    else
      M.cursor = #M.edit_locations
      return fallback_location
    end
  else
    print("[before.nvim]: At the end of the edits list.")
  end
end

local function find_forward_jump(currentLocation)
  local local_cursor = M.cursor
  local lookback_amount = M.cursor
  for i = 0, lookback_amount do
    local_cursor = local_cursor + i
    local location = M.edit_locations[local_cursor]

    if location and should_remove(location) then
      table.remove(M.edit_locations, local_cursor)
    else
      if location and not same_line(currentLocation, location) then
        M.cursor = local_cursor
        return location
      end
    end
  end

  if M.history_wrap_enabled then
    local fallback_location = M.edit_locations[1]
    if fallback_location and should_remove(fallback_location) then
      table.remove(M.edit_locations, 1)
    else
      M.cursor = 1
      return fallback_location
    end
  else
    print("[before.nvim]: At the front of the edits list.")
  end
end

function M.jump_to_last_edit()
  if #M.edit_locations > 0 then
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local current = { bufnr = bufnr, line = pos[1], col = pos[2] }

    local new_location = find_backwards_jump(current)

    if new_location then
      vim.api.nvim_win_set_buf(0, new_location.bufnr)
      vim.api.nvim_win_set_cursor(0, { new_location.line, new_location.col })
    end
  else
    print("[before.nvim]: No edit locations stored.")
  end
end

function M.jump_to_next_edit()
  if #M.edit_locations > 0 then
    local bufnr = vim.api.nvim_get_current_buf()
    local pos = vim.api.nvim_win_get_cursor(0)
    local current = { bufnr = bufnr, line = pos[1], col = pos[2] }

    local new_location = find_forward_jump(current)

    if new_location then
      vim.api.nvim_win_set_buf(0, new_location.bufnr)
      vim.api.nvim_win_set_cursor(0, { new_location.line, new_location.col })
    end
  else
    print("[before.nvim]: No edit locations stored.")
  end
end

M.defaults = {
  history_size = 10,
  history_wrap_enabled = false
}

function M.setup(opts)
  opts = vim.tbl_deep_extend("force", M.defaults, opts or {})

  M.max_entries = opts.history_size
  M.history_wrap_enabled = opts.history_wrap_enabled

  vim.api.nvim_create_autocmd({ "TextChanged", "InsertEnter" }, {
    pattern = "*",
    callback = function()
      require('before').track_edit()
    end,
  })
end

return M
