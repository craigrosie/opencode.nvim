local M = {}
local picker = require('opencode.ui.picker')

local function format_file(path)
  -- when path is something like: file.extension dir1/dir2 -> format to dir1/dir2/file.extension
  local file_match, path_match = path:match('^(.-)\t(.-)$')
  if file_match and path_match then
    path = path_match .. '/' .. file_match
  end

  return {
    name = vim.fn.fnamemodify(path, ':t'),
    path = path,
  }
end

-- Resolves cwd-relative include_paths, filtering out any that don't exist on disk.
local function resolve_include_paths(include_paths)
  local cwd = vim.fn.getcwd()
  local resolved = {}
  for _, p in ipairs(include_paths or {}) do
    if vim.fn.isdirectory(cwd .. '/' .. p) == 1 then
      table.insert(resolved, p)
    end
  end
  return resolved
end

-- Returns the shell command string for listing files in the project (respects .gitignore).
local function detect_base_file_cmd()
  if vim.fn.executable('fd') == 1 then
    return 'fd --type f --color=never'
  elseif vim.fn.executable('fdfind') == 1 then
    return 'fdfind --type f --color=never'
  elseif vim.fn.executable('rg') == 1 then
    return 'rg --files --color=never'
  elseif vim.fn.executable('git') == 1 then
    return 'git ls-files --cached --others --exclude-standard'
  end
  return nil
end

-- Scans each include path for files using git ls-files (bypassing gitignore)
-- or falling back to vim.fn.glob. Returns a list of relative paths and a seen-set.
local function collect_include_files(resolved_paths)
  local files = {}
  local seen = {}
  for _, dir in ipairs(resolved_paths) do
    local result
    if vim.fn.executable('git') == 1 then
      local ok, out = pcall(vim.fn.systemlist, 'git ls-files --cached --others ' .. vim.fn.shellescape(dir))
      if ok and vim.v.shell_error == 0 then
        result = out
      end
    end
    if not result then
      result = vim.fn.glob(dir .. '/**/*', false, true)
      result = vim.tbl_filter(function(f)
        return vim.fn.isdirectory(f) == 0
      end, result)
    end
    for _, f in ipairs(result or {}) do
      if not seen[f] then
        seen[f] = true
        table.insert(files, f)
      end
    end
  end
  return files, seen
end

-- Collects all files: base project files merged with include path files, deduplicated.
local function collect_all_files(resolved_paths)
  local extra_files, seen = collect_include_files(resolved_paths)
  local base_cmd = detect_base_file_cmd()
  if base_cmd then
    local ok, base_files = pcall(vim.fn.systemlist, base_cmd)
    if ok and vim.v.shell_error == 0 and base_files then
      for _, f in ipairs(base_files) do
        if not seen[f] then
          seen[f] = true
          table.insert(extra_files, f)
        end
      end
    end
  end
  table.sort(extra_files)
  return extra_files
end

-- Builds a shell command that lists base project files merged with extra include files.
local function build_merged_cmd(include_files)
  local base_cmd = detect_base_file_cmd()
  if not base_cmd or #include_files == 0 then
    return nil
  end
  local escaped = {}
  for _, f in ipairs(include_files) do
    table.insert(escaped, vim.fn.shellescape(f))
  end
  return string.format(
    "{ %s; printf '%%s\\n' %s; } | awk '!seen[$0]++'",
    base_cmd,
    table.concat(escaped, ' ')
  )
end

local function telescope_ui(callback, path, include_paths)
  local builtin = require('telescope.builtin')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  local attach_mappings = function(prompt_bufnr, map)
    actions.select_default:replace(function()
      local tele_picker = action_state.get_current_picker(prompt_bufnr)
      local multi = tele_picker and tele_picker:get_multi_selection() or {}
      if multi and #multi > 0 then
        actions.close(prompt_bufnr)
        for _, entry in ipairs(multi) do
          if entry and entry.value and callback then
            callback(entry.value)
          end
        end
        return
      end

      local selection = action_state.get_selected_entry()
      actions.close(prompt_bufnr)
      if selection and callback then
        callback(selection.value)
      end
    end)
    return true
  end

  local resolved = resolve_include_paths(include_paths)
  if #resolved > 0 then
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local pickers_mod = require('telescope.pickers')

    local all_files = collect_all_files(resolved)

    pickers_mod.new({}, {
      prompt_title = 'Find Files',
      finder = finders.new_table({ results = all_files }),
      sorter = conf.file_sorter({}),
      previewer = conf.file_previewer({}),
      attach_mappings = attach_mappings,
    }):find()
  else
    local opts = { attach_mappings = attach_mappings }
    if path then
      opts.cwd = path
    end
    builtin.find_files(opts)
  end
end

local function fzf_ui(callback, path, include_paths)
  local fzf_lua = require('fzf-lua')

  local opts = {
    actions = {
      ['default'] = function(selected)
        if not selected or #selected == 0 then
          return
        end

        for _, sel in ipairs(selected) do
          local file = fzf_lua.path.entry_to_file(sel)
          if file and file.path and callback then
            callback(file.path)
          end
        end
      end,
    },
  }

  if path then
    opts.cwd = path
  end

  local resolved = resolve_include_paths(include_paths)
  if #resolved > 0 then
    local include_files = collect_include_files(resolved)
    local merged_cmd = build_merged_cmd(include_files)
    if merged_cmd then
      opts.cmd = merged_cmd
    end
  end

  fzf_lua.files(opts)
end

local function mini_pick_ui(callback, path, include_paths)
  local mini_pick = require('mini.pick')

  local resolved = resolve_include_paths(include_paths)

  local source = {
    choose = function(selected)
      if selected and callback then
        callback(selected)
      end
      return false
    end,
  }

  if #resolved > 0 then
    source.items = function()
      return collect_all_files(resolved)
    end
  elseif path then
    source.cwd = path
  end

  mini_pick.builtin.files(nil, { source = source })
end

local function snacks_picker_ui(callback, path, include_paths)
  local Snacks = require('snacks')

  local origin_win = vim.api.nvim_get_current_win()
  local origin_mode = vim.fn.mode()
  local origin_pos = vim.api.nvim_win_get_cursor(origin_win)

  local confirmed = false

  local opts = {
    confirm = function(picker_obj)
      local items = picker_obj:selected({ fallback = true })
      confirmed = true
      picker_obj:close()

      if items and callback then
        for _, it in ipairs(items) do
          if it and it.file then
            callback(it.file)
          end
        end
      end
    end,
    on_close = function(obj)
      -- snacks doesn't seem to restore window / mode / cursor position when you
      -- cancel the picker. if we pick a file, we're already handling that case elsewhere
      if confirmed or not vim.api.nvim_win_is_valid(origin_win) then
        return
      end

      vim.api.nvim_set_current_win(origin_win)
      if origin_mode:match('i') then
        vim.cmd('startinsert')
      end
      vim.api.nvim_win_set_cursor(origin_win, origin_pos)
    end,
  }

  if path then
    opts.cwd = path
  end

  local resolved = resolve_include_paths(include_paths)
  if #resolved > 0 then
    local include_files = collect_include_files(resolved)
    local merged_cmd = build_merged_cmd(include_files)
    if merged_cmd then
      opts.cmd = merged_cmd
    end
  end

  Snacks.picker.files(opts)
end

function M.pick(callback, path, include_paths)
  local picker_type = picker.get_best_picker()

  if not picker_type then
    return
  end

  local wrapped_callback = function(selected_file)
    local file_name = format_file(selected_file)
    callback(file_name)
  end

  vim.schedule(function()
    if picker_type == 'telescope' then
      telescope_ui(wrapped_callback, path, include_paths)
    elseif picker_type == 'fzf' then
      fzf_ui(wrapped_callback, path, include_paths)
    elseif picker_type == 'mini.pick' then
      mini_pick_ui(wrapped_callback, path, include_paths)
    elseif picker_type == 'snacks' then
      snacks_picker_ui(wrapped_callback, path, include_paths)
    else
      callback(nil)
    end
  end)
end

return M
