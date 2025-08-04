-- UI and interface plugins
return {
    -- Status line
    {
        "nvim-lualine/lualine.nvim",
        dependencies = { "kyazdani42/nvim-web-devicons" },
        config = function()
            require('lualine').setup({
                options = {
                    theme = 'catppuccin'
                }
            })
        end,
    },

    -- Mini.clue for command discovery
    {
        "echasnovski/mini.nvim",
        lazy = false, -- Keep loaded for file browser and command discovery
        config = function()
            -- Setup mini.icons for consistency
            require('mini.icons').setup()
            
            -- Setup mini.files for file navigation
            require('mini.files').setup({
                -- Customization of shown content
                content = {
                    filter = nil, -- Predicate for which file system entries to show
                    prefix = nil, -- What prefix to show to the left of file system entry
                    sort = nil,   -- In what order to show file system entries
                },
                
                -- Module mappings created only inside explorer buffer
                mappings = {
                    close       = 'q',
                    go_in       = 'l',     -- Enter directory or open file
                    go_in_plus  = 'L',     -- Enter directory or open file in new tab
                    go_out      = 'h',     -- Go to parent directory
                    go_out_plus = 'H',     -- Go to parent and close current
                    reset       = '<BS>',  -- Reset to original directory
                    reveal_cwd  = '@',     -- Reveal current working directory
                    show_help   = 'g?',    -- Show help
                    synchronize = '=',     -- Synchronize from file system
                    trim_left   = '<',     -- Trim from left
                    trim_right  = '>',     -- Trim from right
                },
                
                -- General options
                options = {
                    permanent_delete = true,  -- Whether to delete permanently or to trash
                    use_as_default_explorer = false, -- Don't replace netrw automatically
                },
                
                -- Customization of explorer windows
                windows = {
                    max_number = math.huge, -- Maximum number of windows to show
                    preview = true,         -- Whether to show preview of file
                    width_focus = 25,       -- Width of focused window
                    width_nofocus = 15,     -- Width of non-focused window
                    width_preview = 40,     -- Width of preview window
                },
            })
            
            -- File browser keybinding (replaces telescope-file-browser)
            vim.keymap.set('n', '<leader>ne', function()
                require('mini.files').open()
            end, { desc = 'File browser' })
            
            -- Additional useful keybindings
            vim.keymap.set('n', '<leader>nf', function()
                require('mini.files').open(vim.api.nvim_buf_get_name(0), false)
            end, { desc = 'File browser (current file)' })
            
            vim.keymap.set('n', '<leader>nc', function()
                require('mini.files').open(vim.fn.getcwd(), false)
            end, { desc = 'File browser (cwd)' })
            
            local miniclue = require('mini.clue')
            miniclue.setup({
                -- Window options
                window = {
                    delay = 200,
                    config = {
                        border = 'rounded',
                        width = 'auto',
                    },
                },
                -- Clue triggers
                triggers = {
                    -- Leader triggers
                    { mode = 'n', keys = '<Leader>' },
                    { mode = 'x', keys = '<Leader>' },
                    { mode = 'n', keys = '<LocalLeader>' },
                    { mode = 'x', keys = '<LocalLeader>' },
                    
                    -- Built-in completion
                    { mode = 'i', keys = '<C-x>' },
                    
                    -- `g` key
                    { mode = 'n', keys = 'g' },
                    { mode = 'x', keys = 'g' },
                    
                    -- Marks
                    { mode = 'n', keys = "'" },
                    { mode = 'n', keys = '`' },
                    { mode = 'x', keys = "'" },
                    { mode = 'x', keys = '`' },
                    
                    -- Registers
                    { mode = 'n', keys = '"' },
                    { mode = 'x', keys = '"' },
                    { mode = 'i', keys = '<C-r>' },
                    { mode = 'c', keys = '<C-r>' },
                    
                    -- Window commands
                    { mode = 'n', keys = '<C-w>' },
                    
                    -- `z` key
                    { mode = 'n', keys = 'z' },
                    { mode = 'x', keys = 'z' },
                },
                
                -- Clue content
                clues = {
                    -- Enhance this by adding descriptions for <Leader> mapping groups
                    miniclue.gen_clues.builtin_completion(),
                    miniclue.gen_clues.g(),
                    miniclue.gen_clues.marks(),
                    miniclue.gen_clues.registers(),
                    miniclue.gen_clues.windows(),
                    miniclue.gen_clues.z(),
                    
                    -- Custom leader key group descriptions
                    { mode = 'n', keys = '<Leader>b',  desc = '+Buffer' },
                    { mode = 'n', keys = '<Leader>c',  desc = '+Code' },
                    { mode = 'n', keys = '<Leader>d',  desc = '+Diagnostics/Debug' },
                    { mode = 'n', keys = '<Leader>n',  desc = '+Navigate' },
                    { mode = 'n', keys = '<Leader>p',  desc = '+Preview' },
                    { mode = 'n', keys = '<Leader>r',  desc = '+Run/Rename' },
                    { mode = 'n', keys = '<Leader>s',  desc = '+Send/Session' },
                    { mode = 'n', keys = '<Leader>t',  desc = '+Tab' },
                    { mode = 'n', keys = '<Leader>v',  desc = '+View/Inspect' },
                    
                    -- Specific leader key mappings (will inherit from keymap descriptions)
                    -- Buffer operations
                    { mode = 'n', keys = '<Leader>bn', desc = 'Next buffer' },
                    { mode = 'n', keys = '<Leader>bp', desc = 'Previous buffer' },
                    { mode = 'n', keys = '<Leader>bf', desc = 'First buffer' },
                    { mode = 'n', keys = '<Leader>bl', desc = 'Last buffer' },
                    
                    -- Diagnostics and debugging
                    { mode = 'n', keys = '<Leader>dj', desc = 'Next diagnostic' },
                    { mode = 'n', keys = '<Leader>dk', desc = 'Previous diagnostic' },
                    { mode = 'n', keys = '<Leader>dl', desc = 'List diagnostics' },
                    { mode = 'n', keys = '<Leader>dr', desc = 'DAP REPL' },
                    { mode = 'n', keys = '<Leader>dt', desc = 'Debug test' },
                    
                    -- Navigation
                    { mode = 'n', keys = '<Leader>ne', desc = 'File browser' },
                    
                    -- Preview
                    { mode = 'n', keys = '<Leader>p',  desc = 'Glow markdown preview' },
                    
                    -- Run/Rename operations  
                    { mode = 'n', keys = '<Leader>r',  desc = 'LSP rename' },
                    { mode = 'n', keys = '<Leader>rd', desc = 'R devtools::document()' },
                    { mode = 'n', keys = '<Leader>rf', desc = 'R format' },
                    { mode = 'n', keys = '<Leader>rh', desc = 'R help' },
                    { mode = 'n', keys = '<Leader>rl', desc = 'R devtools::load_all()' },
                    { mode = 'n', keys = '<Leader>rt', desc = 'R devtools::test()' },
                    
                    -- Send/Session operations
                    { mode = 'n', keys = '<Leader>se', desc = 'Send line to REPL' },
                    { mode = 'n', keys = '<Leader>sf', desc = 'Find hobby files' },
                    { mode = 'n', keys = '<Leader>sR', desc = 'Send region to REPL' },
                    { mode = 'n', keys = '<Leader>ss', desc = 'Start R session' },
                    
                    -- View/Inspect operations
                    { mode = 'n', keys = '<Leader>vd', desc = 'View dataframe' },
                    { mode = 'n', keys = '<Leader>vh', desc = 'Head' },
                    { mode = 'n', keys = '<Leader>vl', desc = 'Length' },
                    { mode = 'n', keys = '<Leader>vn', desc = 'Names' },
                    { mode = 'n', keys = '<Leader>vs', desc = 'Summary' },
                    { mode = 'n', keys = '<Leader>vt', desc = 'Structure' },
                    
                    -- Code actions
                    { mode = 'n', keys = '<Leader>ca', desc = 'Code action' },
                    
                    -- Miscellaneous
                    { mode = 'n', keys = '<Leader><CR>', desc = 'Reload config' },
                    { mode = 'n', keys = '<Leader>B',   desc = 'Conditional breakpoint' },
                    { mode = 'n', keys = '<Leader>lp',  desc = 'Log point' },
                    { mode = 'n', keys = '<Leader>pi',  desc = 'Pipe insert' },
                },
            })
        end,
    },

    -- Todo comments
    {
        "folke/todo-comments.nvim",
        lazy = true,
        event = { "BufRead", "BufNewFile" },
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("todo-comments").setup()
        end,
    },
}
