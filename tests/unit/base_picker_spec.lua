describe('opencode.ui.base_picker', function()
  local base_picker
  local captured_opts
  local original_schedule
  local saved_modules

  before_each(function()
    original_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end

    saved_modules = {
      ['opencode.config'] = package.loaded['opencode.config'],
      ['opencode.util'] = package.loaded['opencode.util'],
      ['opencode.promise'] = package.loaded['opencode.promise'],
      ['opencode.ui.picker'] = package.loaded['opencode.ui.picker'],
      ['opencode.ui.base_picker'] = package.loaded['opencode.ui.base_picker'],
      ['snacks'] = package.loaded['snacks'],
    }

    package.loaded['opencode.config'] = {
      ui = {
        picker_width = 80,
      },
      debug = {
        show_ids = false,
      },
    }

    package.loaded['opencode.util'] = {}

    package.loaded['opencode.promise'] = {
      wrap = function(value)
        return {
          and_then = function(_, cb)
            cb(value)
          end,
        }
      end,
    }

    package.loaded['opencode.ui.picker'] = {
      get_best_picker = function()
        return 'snacks'
      end,
    }

    captured_opts = nil
    package.loaded['snacks'] = {
      picker = {
        pick = function(opts)
          captured_opts = opts
        end,
      },
    }

    package.loaded['opencode.ui.base_picker'] = nil
    base_picker = require('opencode.ui.base_picker')
  end)

  after_each(function()
    vim.schedule = original_schedule

    for module_name, module_value in pairs(saved_modules) do
      package.loaded[module_name] = module_value
    end
  end)

  it('configures snacks picker to preserve source ordering', function()
    base_picker.pick({
      title = 'Select model',
      items = {
        { name = 'favorite model' },
        { name = 'other model' },
      },
      format_fn = function(item)
        return base_picker.create_picker_item({
          { text = item.name },
        })
      end,
      actions = {},
      callback = function() end,
    })

    assert.is_not_nil(captured_opts)
    assert.are.same(false, captured_opts.matcher.sort_empty)
    assert.are.same({ 'score:desc', 'idx' }, captured_opts.sort.fields)
  end)

  it('assigns stable idx values in snacks transform', function()
    base_picker.pick({
      title = 'Select model',
      items = {
        { name = 'favorite model' },
      },
      format_fn = function(item)
        return base_picker.create_picker_item({
          { text = item.name },
        })
      end,
      actions = {},
      callback = function() end,
    })

    assert.is_not_nil(captured_opts)

    local item = { name = 'favorite model' }
    captured_opts.transform(item, { idx = 7 })

    assert.equal(7, item.idx)
    assert.equal('favorite model', item.text)
  end)

  it('boosts score for favorites in snacks transform', function()
    base_picker.pick({
      title = 'Select model',
      items = {
        { name = 'favorite model', favorite_index = 1 },
      },
      format_fn = function(item)
        return base_picker.create_picker_item({
          { text = item.name },
        })
      end,
      actions = {},
      callback = function() end,
    })

    assert.is_not_nil(captured_opts)

    local item = { name = 'favorite model', favorite_index = 2 }
    captured_opts.transform(item, { idx = 3 })

    assert.equal(998000, item.score_add)
  end)
end)

describe('opencode.ui.base_picker telescope', function()
  local base_picker
  local captured_sorter
  local original_schedule
  local saved_modules

  before_each(function()
    original_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end

    saved_modules = {
      ['opencode.config'] = package.loaded['opencode.config'],
      ['opencode.util'] = package.loaded['opencode.util'],
      ['opencode.promise'] = package.loaded['opencode.promise'],
      ['opencode.ui.picker'] = package.loaded['opencode.ui.picker'],
      ['opencode.ui.base_picker'] = package.loaded['opencode.ui.base_picker'],
      ['telescope.pickers'] = package.loaded['telescope.pickers'],
      ['telescope.finders'] = package.loaded['telescope.finders'],
      ['telescope.config'] = package.loaded['telescope.config'],
      ['telescope.actions'] = package.loaded['telescope.actions'],
      ['telescope.actions.state'] = package.loaded['telescope.actions.state'],
      ['telescope.actions.utils'] = package.loaded['telescope.actions.utils'],
      ['telescope.pickers.entry_display'] = package.loaded['telescope.pickers.entry_display'],
    }

    package.loaded['opencode.config'] = {
      ui = {
        picker_width = 80,
      },
      debug = {
        show_ids = false,
      },
    }

    package.loaded['opencode.util'] = {}

    package.loaded['opencode.promise'] = {
      wrap = function(value)
        return {
          and_then = function(_, cb)
            cb(value)
          end,
        }
      end,
    }

    package.loaded['opencode.ui.picker'] = {
      get_best_picker = function()
        return 'telescope'
      end,
    }

    captured_sorter = nil

    local mock_picker_instance = {
      find = function() end,
    }

    package.loaded['telescope.pickers'] = {
      new = function(_, picker_opts)
        captured_sorter = picker_opts.sorter
        return mock_picker_instance
      end,
    }

    package.loaded['telescope.finders'] = {
      new_table = function(tbl_opts)
        return { results = tbl_opts.results, entry_maker = tbl_opts.entry_maker }
      end,
    }

    package.loaded['telescope.config'] = {
      values = {
        generic_sorter = function()
          return {
            scoring_function = function(_, _, _, _)
              return 5
            end,
          }
        end,
      },
    }

    local noop = function() end
    package.loaded['telescope.actions'] = {
      select_default = { replace = noop },
      close = { enhance = noop },
    }

    package.loaded['telescope.actions.state'] = {
      get_selected_entry = noop,
    }

    package.loaded['telescope.actions.utils'] = {
      map_selections = noop,
    }

    package.loaded['telescope.pickers.entry_display'] = {
      create = function()
        return function(parts)
          return parts
        end
      end,
    }

    package.loaded['opencode.ui.base_picker'] = nil
    base_picker = require('opencode.ui.base_picker')
  end)

  after_each(function()
    vim.schedule = original_schedule

    for module_name, module_value in pairs(saved_modules) do
      package.loaded[module_name] = module_value
    end
  end)

  it('boosts score for favorites in telescope sorter', function()
    base_picker.pick({
      title = 'Select model',
      items = {
        { name = 'favorite model', favorite_index = 1 },
        { name = 'other model', favorite_index = 999 },
      },
      format_fn = function(item)
        return base_picker.create_picker_item({
          { text = item.name },
        })
      end,
      actions = {},
      callback = function() end,
    })

    assert.is_not_nil(captured_sorter)

    local fav_entry = { value = { favorite_index = 1 } }
    local normal_entry = { value = { favorite_index = 999 } }

    local fav_score = captured_sorter:scoring_function('test', 'favorite model', fav_entry)
    local normal_score = captured_sorter:scoring_function('test', 'other model', normal_entry)

    assert.is_true(fav_score > normal_score)
    assert.is_true(fav_score > 0)
  end)

  it('preserves filtered-out entries in telescope sorter', function()
    package.loaded['telescope.config'] = {
      values = {
        generic_sorter = function()
          return {
            scoring_function = function(_, _, _, _)
              return 0
            end,
          }
        end,
      },
    }

    package.loaded['opencode.ui.base_picker'] = nil
    base_picker = require('opencode.ui.base_picker')

    base_picker.pick({
      title = 'Select model',
      items = {
        { name = 'favorite model', favorite_index = 1 },
      },
      format_fn = function(item)
        return base_picker.create_picker_item({
          { text = item.name },
        })
      end,
      actions = {},
      callback = function() end,
    })

    assert.is_not_nil(captured_sorter)

    local fav_entry = { value = { favorite_index = 1 } }
    local score = captured_sorter:scoring_function('xyz', 'favorite model', fav_entry)

    assert.equal(0, score)
  end)

  it('does not boost non-favorite entries in telescope sorter', function()
    base_picker.pick({
      title = 'Select model',
      items = {
        { name = 'other model', favorite_index = 999 },
      },
      format_fn = function(item)
        return base_picker.create_picker_item({
          { text = item.name },
        })
      end,
      actions = {},
      callback = function() end,
    })

    assert.is_not_nil(captured_sorter)

    local normal_entry = { value = { favorite_index = 999 } }
    local score = captured_sorter:scoring_function('test', 'other model', normal_entry)

    assert.equal(5, score)
  end)
end)
