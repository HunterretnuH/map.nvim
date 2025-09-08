local M = {}

M.keys = {}
M.mapRegistry = {}
M.cmds = {}

-- Function to check if a value exists in a table
local function contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

local function add_notify(rhs, notify)

    if type(rhs) == "function" then
        if notify then
            return function(...)
                rhs(...)
                vim.notify(notify)
            end
        else
            return rhs
        end
    elseif type(rhs) == "string" then
        if notify then
            return rhs .. ':lua vim.notify("' .. notify .. '")<CR>'
        else
            return rhs
        end
    else
        error("rhs must be function or string")
    end
end

-- Wrapper function for creating keymappings. Accepts the same fields as lazy.nvim's `keys` spec
-- Example: map("n", "<leader>x", ":echo 'Hello'<CR>", { desc = "Say hello" })
function M.map(mode, lhs, rhs, opts)
    opts = opts or {}

    -- Normalize mode into a table i.e. 'n' -> { 'n' }.
    if type(mode) == "string" then
        mode = { mode }
    end

    if type(rhs) == "table" then
        local plugin_cmd = rhs.plugin_command
        rhs = rhs.call
        table.insert(M.cmds, plugin_cmd)
    end

    -- Add notification based on description
    -- TODO: Temporarily disabled. I need to check which keybinding it breakes and add notify = false.
--  local notify = opts.notify or true
    opts.notify = nil
--  if notify and not contains(mode, 'i') then
--      rhs = add_notify(rhs, opts.desc)
--  end

    local mapping = {
        lhs,
        rhs,
        mode = mode,
        desc = opts.desc,
        silent = opts.silent,
        noremap = opts.noremap,
        expr = opts.expr,
    }

     -- Check for duplicates and save used mappings and modes in registry
    M.mapRegistry[lhs] = M.mapRegistry[lhs] or {}
    for _, m in ipairs(mode) do
        if not M.mapRegistry[lhs][m] == rhs then
            vim.notify(
                string.format("Warning: Duplicate mapping detected for '%s' (mode: %s): %s",
                              lhs, m, vim.inspect(mapping)), vim.log.levels.WARN
            )
        else
            M.mapRegistry[lhs][m] = rhs
        end
    end

    -- Append to local keys list used by export()
    table.insert(M.keys, mapping)

    vim.keymap.set(mode, lhs, rhs, opts)
    -- vim.notify(string.format("'%s': %s", lhs, vim.inspect(rhs))) -- DEBUG LOG

    -- Register binding for map-tree if available
    local ok, mt = pcall(require, "map-tree")
    if ok then
        mt.register(lhs, opts.desc)
    end
end

-- Export keys and clean local keys list
function M.exportKeys()
    local keys = M.keys
    M.keys = {}
    return keys
end

-- Export cmds and clean local keys list
function M.exportCmds()
    local cmds = M.cmds
    M.cmds = {}
    return cmds
end

-- Wrapper function for creating grups.
-- Example: group("<leader>g", group = "GROUP NAME")
function M.group(lhs, opts)
    opts = opts or {}
    local group = opts.group or ""

     -- Check for duplicate
    M.mapRegistry[lhs] = M.mapRegistry[lhs] or {}
    if not M.mapRegistry[lhs] == group and M.mapRegistry[lhs].mode == "" then
        vim.notify(
            string.format("Warning: Duplicate group registration detected for group '%s': %s", lhs, vim.inspect(opts)),
            vim.log.levels.WARN
        )
    else
        -- Mark in keys registry used to detect duplicate mappings
        -- TODO: Check how "group" pseudo-mode interacts with mode check for notify
        M.mapRegistry[lhs]["group"] = group
    end

  -- If which-key is available, register this group in it.
    local wk_ok, wk = pcall(require, "which-key")
    if wk_ok then
      wk.register({ [lhs] = opts })
    end

    -- Register binding for map-tree if available
    local mt_ok, mt = pcall(require, "map-tree")
    if mt_ok then
        mt.register(lhs, group)
    end
end

-- Wrapper for functions
-- TODO: Check if it works with nested modules
--function M.func(module, fn)
--  return function(...)
--    return require(module)[fn](...)
--  end
--end

function M.func(func_path)
  local parts = {}
  for part in string.gmatch(func_path, "[^%.]+") do
    table.insert(parts, part)
  end

  return function(...)
    local obj = require(parts[1])
    for i = 2, #parts - 1 do
      obj = obj[parts[i]]
      if not obj then
        error("Invalid path: "..table.concat(parts, ".", 1, i))
      end
    end
    local fn = obj[parts[#parts]]
    if type(fn) ~= "function" then
      error("Not a function: "..func_path)
    end
    return fn(...)
  end
end

-- Wrapper for plugin commands
function M.plug_cmd(name)
    local t = {}
    t.plugin_command = name
    t.call = function() vim.cmd(name) end
    return t
end

-- Wrapper for plugin commands
function M.cmd(name)
    return function() vim.cmd(name) end
end

return M

-- TODO:
-- * Remove or finish work on plug_cmd and exportCmds
-- * verify what happens when M.exportKeys() is not called by some mappings 
--   and then plugin calls it to register it's own mappings via keys field mappings.

