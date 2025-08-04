-- ================================================================================
-- General settings
-- ================================================================================

-- Enable syntax highlighting
vim.cmd('syntax on')

-- Basic editor settings
vim.opt.modifiable = true
vim.opt.mouse = 'a'
vim.opt.cursorline = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.softtabstop = 4
vim.opt.expandtab = true
vim.opt.autoread = true
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.swapfile = false
vim.opt.number = true
vim.opt.foldlevelstart = 99
vim.opt.scrolloff = 7
vim.opt.shortmess:append('I')

-- Undo settings
vim.opt.undofile = true
vim.opt.undodir = vim.fn.expand('~/.config/nvim/undo')
vim.opt.undolevels = 1000
vim.opt.undoreload = 10000

-- Show tabline only when there are multiple tabs
vim.opt.showtabline = 1

-- Use system clipboard
vim.opt.clipboard = 'unnamedplus'

-- Encoding
vim.opt.encoding = 'UTF-8'

-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- ================================================================================
-- Key mappings
-- ================================================================================

-- Navigate buffers
vim.keymap.set('n', '<leader>bn', ':bnext<CR>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bp', ':bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<leader>bf', ':bfirst<CR>', { desc = 'First buffer' })
vim.keymap.set('n', '<leader>bl', ':blast<CR>', { desc = 'Last buffer' })

-- Navigate tabs
vim.keymap.set('n', '<leader>tn', ':tabnext<CR>', { desc = 'Next tab' })
vim.keymap.set('n', '<leader>tp', ':tabprevious<CR>', { desc = 'Previous tab' })
vim.keymap.set('n', '<leader>tf', ':tabfirst<CR>', { desc = 'First tab' })
vim.keymap.set('n', '<leader>tl', ':tablast<CR>', { desc = 'Last tab' })
vim.keymap.set('n', '<leader>tc', ':tabclose<CR>', { desc = 'Close tab' })
vim.keymap.set('n', '<leader>to', ':tabonly<CR>', { desc = 'Close other tabs' })
vim.keymap.set('n', '<leader>tt', ':tabnew<CR>', { desc = 'New tab' })

-- Other mappings
vim.keymap.set('n', '<leader><CR>', ':source ~/.config/nvim/init.lua<CR>', { desc = 'Reload config' })

-- Focus and redistribute split windows
vim.keymap.set('n', 'ff', ':resize 100<CR>:vertical resize 220<CR>', { desc = 'Focus window' })
vim.keymap.set('n', 'fm', '<C-w>=', { desc = 'Redistribute windows' })

-- ================================================================================
-- File type specific settings
-- ================================================================================

-- Stata configuration
vim.api.nvim_create_autocmd({'BufNewFile', 'BufRead'}, {
    pattern = {'*.do', '*.ado'},
    callback = function()
        vim.bo.filetype = 'stata'
    end
})

vim.api.nvim_create_autocmd('FileType', {
    pattern = 'stata',
    callback = function()
        vim.opt_local.tabstop = 4
        vim.opt_local.shiftwidth = 4
        vim.opt_local.softtabstop = 4
        vim.opt_local.expandtab = true
        vim.opt_local.commentstring = '* %s'
    end
})

-- Go - format on save
vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = '*.go',
    callback = function()
        vim.lsp.buf.format()
    end
})

-- Python configuration
vim.api.nvim_create_autocmd('FileType', {
    pattern = 'python',
    callback = function()
        -- Follow your coding rules: 4 spaces, 80 char limit
        vim.opt_local.tabstop = 4
        vim.opt_local.shiftwidth = 4
        vim.opt_local.softtabstop = 4
        vim.opt_local.expandtab = true
        vim.opt_local.textwidth = 80
        vim.opt_local.colorcolumn = '80'
        vim.opt_local.commentstring = '# %s'
        
        -- Python-specific keybindings
        local opts = { buffer = true, silent = true }
        
        -- Run current file
        vim.keymap.set('n', '<F5>', function()
            local file_path = vim.fn.expand('%:p')
            vim.cmd('split | terminal python "' .. file_path .. '"')
        end, vim.tbl_extend('force', opts, { desc = 'Run Python file' }))
        
        -- Run current line/selection in Python REPL (if available)
        vim.keymap.set('n', '<F9>', function()
            local current_line = vim.api.nvim_get_current_line()
            if current_line:match('^%s*$') then return end
            -- This would need python REPL integration
            print('Would run in Python: ' .. current_line)
        end, vim.tbl_extend('force', opts, { desc = 'Run current line in Python' }))
    end
})

-- JavaScript/TypeScript configuration
vim.api.nvim_create_autocmd('FileType', {
    pattern = {'javascript', 'typescript', 'javascriptreact', 'typescriptreact'},
    callback = function()
        -- Follow your coding rules: 4 spaces (unless file uses 2), 80 char limit
        local current_indent = vim.fn.indent(1)
        if current_indent == 2 then
            vim.opt_local.tabstop = 2
            vim.opt_local.shiftwidth = 2
            vim.opt_local.softtabstop = 2
        else
            vim.opt_local.tabstop = 4
            vim.opt_local.shiftwidth = 4
            vim.opt_local.softtabstop = 4
        end
        vim.opt_local.expandtab = true
        vim.opt_local.textwidth = 80
        vim.opt_local.colorcolumn = '80'
        vim.opt_local.commentstring = '// %s'
        
        -- JavaScript/TypeScript-specific keybindings
        local opts = { buffer = true, silent = true }
        
        -- Run with Node.js (for .js files)
        if vim.bo.filetype == 'javascript' then
            vim.keymap.set('n', '<F5>', function()
                local file_path = vim.fn.expand('%:p')
                vim.cmd('split | terminal node "' .. file_path .. '"')
            end, vim.tbl_extend('force', opts, { desc = 'Run with Node.js' }))
        end
        
        -- TypeScript compilation (for .ts files)
        if vim.bo.filetype == 'typescript' then
            vim.keymap.set('n', '<F5>', function()
                local file_path = vim.fn.expand('%:p')
                vim.cmd('split | terminal npx ts-node "' .. file_path .. '"')
            end, vim.tbl_extend('force', opts, { desc = 'Run with ts-node' }))
            
            vim.keymap.set('n', '<leader>tc', function()
                local file_path = vim.fn.expand('%:p')
                vim.cmd('split | terminal npx tsc "' .. file_path .. '"')
            end, vim.tbl_extend('force', opts, { desc = 'Compile TypeScript' }))
        end
    end
})

-- ================================================================================
-- FZF settings
-- ================================================================================

-- Set FZF default options
vim.env.FZF_DEFAULT_OPTS = '--reverse'

-- ================================================================================
-- Bootstrap lazy.nvim
-- ================================================================================

require("config.lazy")

-- ================================================================================
-- Legacy settings (will be moved to plugin configs)
-- ================================================================================

-- Glow settings
vim.g.glow_use_pager = false

-- Markdown Preview settings
vim.g.mkdp_auto_start = 0
vim.g.mkdp_auto_close = 1
vim.g.mkdp_refresh_slow = 0
vim.g.mkdp_command_for_global = 1
vim.g.mkdp_open_to_the_world = 0
vim.g.mkdp_open_ip = ''
vim.g.mkdp_browser = ''
vim.g.mkdp_echo_preview_url = 0
vim.g.mkdp_browserfunc = ''
vim.g.mkdp_preview_options = {
    mkit = {},
    katex = {},
    uml = {},
    maid = {},
    disable_sync_scroll = 0,
    sync_scroll_type = 'middle',
    hide_yaml_meta = 1,
    sequence_diagrams = {},
    flowchart_diagrams = {},
    content_editable = false,
    disable_filename = 0
}
vim.g.mkdp_markdown_css = ''
vim.g.mkdp_highlight_css = ''
vim.g.mkdp_port = ''
vim.g.mkdp_page_title = '「${name}」'
vim.g.mkdp_filetypes = {'markdown'}

-- Markdown preview keybinding
vim.keymap.set('n', '<C-p>', ':MarkdownPreview<CR>', { desc = 'Markdown preview' })

-- Legacy Telescope keybindings (will be moved to plugin config)
vim.keymap.set('n', '<C-_>', function()
    require('telescope.builtin').current_buffer_fuzzy_find({
        sorting_strategy = "ascending",
        prompt_position = "top"
    })
end, { desc = 'Search current buffer' })

vim.keymap.set('n', '<F4>', function()
    package.loaded.init = nil
    vim.cmd('source ~/.config/nvim/init.lua')
end, { desc = 'Reload and source config' })

