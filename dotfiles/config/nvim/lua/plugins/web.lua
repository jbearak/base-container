-- Web development specific plugins
return {
    -- JavaScript/TypeScript language support enhancements
    {
        "pangloss/vim-javascript",
        ft = "javascript",
    },
    
    {
        "leafgarland/typescript-vim", 
        ft = "typescript",
    },
    
    {
        "maxmellon/vim-jsx-pretty",
        ft = {"javascript", "javascriptreact", "typescript", "typescriptreact"},
        config = function()
            vim.g.vim_jsx_pretty_colorful_config = 1
        end,
    },
    
    {
        "jparise/vim-graphql",
        ft = {"graphql", "javascript", "typescript"},
    },
    
    -- Emmet for HTML/CSS
    {
        "mattn/emmet-vim",
        ft = {"html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact"},
        config = function()
            -- Enable emmet for jsx
            vim.g.user_emmet_settings = {
                javascript = {
                    extends = 'jsx',
                },
                typescript = {
                    extends = 'tsx',
                },
            }
            
            -- Set emmet leader key
            vim.g.user_emmet_leader_key = '<C-Z>'
            
            -- File type specific settings
            vim.api.nvim_create_autocmd("FileType", {
                pattern = {"html", "css", "javascript", "javascriptreact", "typescript", "typescriptreact"},
                callback = function()
                    local opts = { buffer = true, silent = true }
                    
                    -- Emmet expand abbreviation
                    vim.keymap.set({'n', 'i'}, '<C-z>,', '<plug>(emmet-expand-abbr)', 
                        vim.tbl_extend('force', opts, { desc = 'Emmet expand abbreviation' }))
                    
                    -- Emmet wrap with abbreviation
                    vim.keymap.set('v', '<C-z>,', '<plug>(emmet-expand-abbr)', 
                        vim.tbl_extend('force', opts, { desc = 'Emmet wrap with abbreviation' }))
                end
            })
        end,
    },
    
    -- Additional web development tools
    {
        "prettier/vim-prettier",
        build = "yarn install --frozen-lockfile --production",
        ft = {"javascript", "typescript", "css", "scss", "json", "graphql", "markdown", "vue", "yaml", "html"},
        config = function()
            -- Auto format files on save
            vim.g.prettier_autoformat = 1
            vim.g.prettier_autoformat_require_pragma = 0
            
            -- Prettier configuration following your coding rules
            vim.g.prettier_config_precedence = 'file-override'
            vim.g.prettier_tab_width = 4  -- Default to 4 spaces per your rules
            vim.g.prettier_use_tabs = 'false'
            vim.g.prettier_print_width = 80  -- 80 char line limit per your rules
            vim.g.prettier_single_quote = 'true'
            vim.g.prettier_trailing_comma = 'es5'
            
            -- File type specific prettier settings
            vim.api.nvim_create_autocmd("FileType", {
                pattern = {"javascript", "typescript", "css", "scss", "json", "graphql", "yaml", "html"},
                callback = function()
                    local opts = { buffer = true, silent = true }
                    
                    -- Manual format with prettier
                    vim.keymap.set('n', '<leader>fp', ':Prettier<CR>', 
                        vim.tbl_extend('force', opts, { desc = 'Format with Prettier' }))
                end
            })
        end,
    },
}
