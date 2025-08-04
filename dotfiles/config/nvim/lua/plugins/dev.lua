-- Development tools and debugging
return {
    -- Iron.nvim for REPL integration
    {
        "Vigemus/iron.nvim",
        config = function()
            local iron = require("iron.core")
            
            iron.setup({
                config = {
                    -- Whether a repl should be discarded or not
                    scratch_repl = true,
                    -- Your repl definitions come here
                    repl_definition = {
                        r = {
                            -- Can be a table or a function that returns a table
                            command = {"R"}
                        }
                    },
                    -- How the repl window will be displayed
                    repl_open_cmd = require("iron.view").bottom(15)
                },
                -- Iron doesn't set keymaps by default anymore.
                -- You can set them here or manually add keymaps to the functions in iron.core
                keymaps = {
                    send_motion = "<space>sc",
                    visual_send = "<space>sc",
                    send_file = "<space>sf",
                    send_line = "<space>sl",
                    send_paragraph = "<space>sp",
                    send_until_cursor = "<space>su",
                    send_mark = "<space>sm",
                    mark_motion = "<space>mc",
                    mark_visual = "<space>mc",
                    remove_mark = "<space>md",
                    cr = "<space>s<cr>",
                    interrupt = "<space>s<space>",
                    exit = "<space>sq",
                    clear = "<space>cl",
                },
                -- If the highlight is on, you can change how it looks
                highlight = {
                    italic = true,
                },
                ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
            })
            
            -- Iron also has a list of commands, see :h iron-commands for all available commands
            vim.keymap.set("n", "<space>rs", "<cmd>IronRepl<cr>")
            vim.keymap.set("n", "<space>rr", "<cmd>IronRestart<cr>")
            vim.keymap.set("n", "<space>rf", "<cmd>IronFocus<cr>")
            vim.keymap.set("n", "<space>rh", "<cmd>IronHide<cr>")
            
            -- R-specific keybindings
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "r",
                callback = function()
                    local opts = { buffer = true, silent = true }
                    
                    -- Set localleader to comma for R files
                    vim.g.maplocalleader = ","
                    
                    -- Set comment string for R files
                    vim.opt_local.commentstring = "# %s"
                    
                    -- File operations
                    vim.keymap.set("n", "<leader>ss", function()
                        vim.cmd("write")
                        vim.cmd("IronSend source('" .. vim.fn.expand("%:p") .. "')")
                    end, vim.tbl_extend("force", opts, { desc = "Save and source file" }))
                    
                    vim.keymap.set("n", "<leader>se", function()
                        vim.cmd("write")
                        vim.cmd("IronSend source('" .. vim.fn.expand("%:p") .. "', echo = TRUE)")
                    end, vim.tbl_extend("force", opts, { desc = "Save and source with echo" }))
                    
                    vim.keymap.set("n", "<leader>sR", function()
                        vim.cmd("write")
                        vim.cmd("IronSend rm(list = ls())")
                        vim.cmd("IronSend source('" .. vim.fn.expand("%:p") .. "')")
                    end, vim.tbl_extend("force", opts, { desc = "Clear workspace and source" }))
                    
                    -- RStudio-like behavior
                    vim.keymap.set("n", "<C-CR>", function()
                        vim.cmd("normal! ^")
                        vim.cmd("IronSend")
                        vim.cmd("normal! j")
                    end, vim.tbl_extend("force", opts, { desc = "Run line and move down" }))
                    
                    vim.keymap.set("v", "<C-CR>", "<Plug>(iron-send-motion)", 
                        vim.tbl_extend("force", opts, { desc = "Run selection" }))
                    
                    -- Data exploration
                    local explore_keys = {
                        ["<leader>vd"] = { cmd = "View", desc = "View dataframe" },
                        ["<leader>vs"] = { cmd = "summary", desc = "Summary" },
                        ["<leader>vt"] = { cmd = "str", desc = "Structure" },
                        ["<leader>vh"] = { cmd = "head", desc = "Head" },
                        ["<leader>vn"] = { cmd = "names", desc = "Names" },
                        ["<leader>vl"] = { cmd = "length", desc = "Length" },
                    }
                    
                    for key, info in pairs(explore_keys) do
                        vim.keymap.set("n", key, function()
                            local word = vim.fn.expand("<cword>")
                            if word ~= "" then
                                vim.cmd("IronSend " .. info.cmd .. "(" .. word .. ")")
                            end
                        end, vim.tbl_extend("force", opts, { desc = info.desc .. " of object under cursor" }))
                    end
                    
                    -- Package development (if devtools is available)
                    vim.keymap.set("n", "<leader>rt", "<cmd>w | IronSend devtools::test()<cr>", 
                        vim.tbl_extend("force", opts, { desc = "Run tests" }))
                    vim.keymap.set("n", "<leader>rl", "<cmd>w | IronSend devtools::load_all()<cr>", 
                        vim.tbl_extend("force", opts, { desc = "Load all" }))
                    vim.keymap.set("n", "<leader>rd", "<cmd>w | IronSend devtools::document()<cr>", 
                        vim.tbl_extend("force", opts, { desc = "Document package" }))
                    
                    -- Package installation helper
                    vim.keymap.set("n", "<leader>pi", function()
                        local line = vim.api.nvim_get_current_line()
                        local package = line:match("library%(([^)]+)%)") or 
                                      line:match('library%("([^"]+)"%)') or 
                                      line:match("library%('([^']+)'%)")
                        if package then
                            -- Remove quotes if present
                            package = package:gsub("^['\"", ""):gsub("['\"]$", "")
                            vim.cmd("IronSend install.packages('" .. package .. "')")
                        else
                            print("No package found on current line")
                        end
                    end, vim.tbl_extend("force", opts, { desc = "Install package from current line" }))
                    
                    -- Help
                    vim.keymap.set("n", "<leader>rh", function()
                        local word = vim.fn.expand("<cword>")
                        if word ~= "" then
                            vim.cmd("IronSend ?" .. word)
                        end
                    end, vim.tbl_extend("force", opts, { desc = "Help for object under cursor" }))
                    
                    -- Run current function
                    vim.keymap.set("n", "<leader>rf", function()
                        -- Save file first
                        vim.cmd("write")
                        
                        -- Get current function name (basic regex, works for simple cases)
                        local line = vim.fn.search("^[[:alnum:]_.]+ <- function", "bnW")
                        if line > 0 then
                            local func_line = vim.fn.getline(line)
                            local func_name = func_line:match("^([[:alnum:]_.]+) <-")
                            if func_name then
                                vim.cmd("IronSend " .. func_name .. "()")
                            else
                                print("Could not find function name")
                            end
                        else
                            print("No function found above cursor")
                        end
                    end, vim.tbl_extend("force", opts, { desc = "Run current function" }))
                end
            })
        end,
    },

    -- Debug Adapter Protocol
    {
        "mfussenegger/nvim-dap",
        lazy = true,
        keys = {
            { "<F5>", ":lua require'dap'.continue()<CR>", desc = "Continue" },
            { "<F3>", ":lua require'dap'.step_over()<CR>", desc = "Step Over" },
            { "<F2>", ":lua require'dap'.step_into()<CR>", desc = "Step Into" },
            { "<F12>", ":lua require'dap'.step_out()<CR>", desc = "Step Out" },
            { "<leader>b", ":lua require'dap'.toggle_breakpoint()<CR>", desc = "Toggle Breakpoint" },
            { "<leader>B", ":lua require'dap'.set_breakpoint(vim.fn.input('Breakpoint condition: '))<CR>", desc = "Conditional Breakpoint" },
            { "<leader>lp", ":lua require'dap'.set_breakpoint(nil, nil, vim.fn.input('Log point message: '))<CR>", desc = "Log Point" },
            { "<leader>dr", ":lua require'dap'.repl.open()<CR>", desc = "DAP REPL" },
            { "<leader>dt", ":lua require'dap-go'.debug_test()<CR>", desc = "Debug Go Test", ft = "go" },
        },
        dependencies = {
            "nvim-neotest/nvim-nio",
            "rcarriga/nvim-dap-ui",
            "theHamsta/nvim-dap-virtual-text",
            "leoluz/nvim-dap-go",
        },
        config = function()
            local dap = require("dap")
            local dapui = require("dapui")
            
            -- Setup DAP UI
            dapui.setup()
            
            -- Setup virtual text
            require("nvim-dap-virtual-text").setup()
            
            -- Setup Go debugging
            require('dap-go').setup()
            
            -- Auto open/close DAP UI
            dap.listeners.after.event_initialized["dapui_config"] = function()
                dapui.open()
            end
            dap.listeners.before.event_terminated["dapui_config"] = function()
                dapui.close()
            end
            dap.listeners.before.event_exited["dapui_config"] = function()
                dapui.close()
            end
            
            -- DAP keybindings are now handled by lazy.nvim keys
        end,
    },

    -- Glow for markdown preview
    {
        "ellisonleao/glow.nvim",
        lazy = true,
        ft = { "markdown", "md" },
        cmd = { "Glow" },
        keys = {
            { "<leader>p", "<cmd>Glow<cr>", desc = "Glow markdown preview", ft = { "markdown", "md" } },
        },
        config = function()
            require("glow").setup({
                border = "shadow",
                style = "dark",
            })
            
            -- Set glow binary path if needed
            vim.g.glow_binary_path = vim.env.HOME .. "/bin"
            vim.g.glow_use_pager = false
            
            -- Glow keybinding is now handled by lazy.nvim keys
        end,
    },

    -- Go language support enhancements
    {
        "ray-x/go.nvim",
        lazy = true,
        ft = { "go", "gomod", "gowork", "gotmpl" },
        dependencies = {
            "ray-x/guihua.lua",
            "neovim/nvim-lspconfig",
            "nvim-treesitter/nvim-treesitter",
        },
        config = function()
            require('go').setup({
                -- Enable goimports on save
                goimport = 'gopls',
                -- Format on save
                gofmt = 'gopls',
                -- Tag transform
                tag_transform = false,
                -- Test configurations
                test_dir = '',
                comment_placeholder = '   ',
                -- LSP configuration
                lsp_cfg = false, -- Do not override the lsp setup from lspconfig
                lsp_gofumpt = true,
                lsp_on_attach = false, -- Use our global on_attach
                dap_debug = true,
            })
            
            -- Go-specific keybindings
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "go",
                callback = function()
                    local opts = { buffer = true, silent = true }
                    
                    -- Import management
                    vim.keymap.set("n", "<leader>ia", ":GoImport ", 
                        vim.tbl_extend("force", opts, { desc = "Add import" }))
                    vim.keymap.set("n", "<leader>id", ":GoDrop ", 
                        vim.tbl_extend("force", opts, { desc = "Drop import" }))
                    
                    -- Code generation
                    vim.keymap.set("n", "<leader>gt", ":GoAddTag ", 
                        vim.tbl_extend("force", opts, { desc = "Add struct tags" }))
                    vim.keymap.set("n", "<leader>grt", ":GoRmTag ", 
                        vim.tbl_extend("force", opts, { desc = "Remove struct tags" }))
                    vim.keymap.set("n", "<leader>ie", ":GoIfErr", 
                        vim.tbl_extend("force", opts, { desc = "Generate if err" }))
                    vim.keymap.set("n", "<leader>fs", ":GoFillStruct", 
                        vim.tbl_extend("force", opts, { desc = "Fill struct" }))
                    vim.keymap.set("n", "<leader>fe", ":GoFillSwitch", 
                        vim.tbl_extend("force", opts, { desc = "Fill switch" }))
                    
                    -- Testing
                    vim.keymap.set("n", "<leader>tf", ":GoTest -v", 
                        vim.tbl_extend("force", opts, { desc = "Test function" }))
                    vim.keymap.set("n", "<leader>ta", ":GoTest -v ./...", 
                        vim.tbl_extend("force", opts, { desc = "Test all" }))
                    vim.keymap.set("n", "<leader>tc", ":GoCoverage", 
                        vim.tbl_extend("force", opts, { desc = "Test coverage" }))
                    
                    -- Run
                    vim.keymap.set("n", "<leader>gr", ":GoRun", 
                        vim.tbl_extend("force", opts, { desc = "Go run" }))
                    vim.keymap.set("n", "<leader>gb", ":GoBuild", 
                        vim.tbl_extend("force", opts, { desc = "Go build" }))
                    
                    -- Alternative files
                    vim.keymap.set("n", "<leader>ga", ":GoAlt!", 
                        vim.tbl_extend("force", opts, { desc = "Alternate file" }))
                end
            })
        end,
        event = {"CmdlineEnter"},
        ft = {"go", 'gomod'},
        build = ':lua require("go.install").update_all_sync()'
    },
    
    -- Stata language support 
    {
        "zizhongyan/vim-stata",
        ft = "stata",
        config = function()
            -- Stata-specific settings and keybindings
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "stata",
                callback = function()
                    local opts = { buffer = true, silent = true }
                    
                    -- Set comment string for Stata files (full-line comments)
                    vim.opt_local.commentstring = "* %s"
                    
                    -- Stata-specific keybindings (following your coding rules)
                    -- Run current line in Stata
                    vim.keymap.set("n", "<F9>", function()
                        local current_line = vim.api.nvim_get_current_line()
                        if current_line:match("^%s*$") then return end -- Skip empty lines
                        -- This would need stata integration - placeholder for now
                        print("Would run in Stata: " .. current_line)
                    end, vim.tbl_extend("force", opts, { desc = "Run current line in Stata" }))
                    
                    -- Run selection in Stata
                    vim.keymap.set("v", "<F9>", function()
                        -- Get selected text
                        local start_line = vim.fn.line("v")
                        local end_line = vim.fn.line(".")
                        local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
                        local selection = table.concat(lines, "\n")
                        -- This would need stata integration - placeholder for now
                        print("Would run in Stata: " .. selection)
                    end, vim.tbl_extend("force", opts, { desc = "Run selection in Stata" }))
                    
                    -- Run entire file
                    vim.keymap.set("n", "<F10>", function()
                        local file_path = vim.fn.expand("%:p")
                        -- This would need stata integration - placeholder for now
                        print("Would run file in Stata: " .. file_path)
                    end, vim.tbl_extend("force", opts, { desc = "Run file in Stata" }))
                    
                    -- Insert common Stata patterns following your coding rules
                    vim.keymap.set("n", "<leader>if", "iforeach my_ of local the_<Esc>F_a", 
                        vim.tbl_extend("force", opts, { desc = "Insert foreach loop" }))
                    vim.keymap.set("n", "<leader>ig", "igen variable_name_units = <Esc>F_a", 
                        vim.tbl_extend("force", opts, { desc = "Insert gen command" }))
                    
                    -- Data inspection shortcuts
                    vim.keymap.set("n", "<leader>sd", "isummarize <Esc>a", 
                        vim.tbl_extend("force", opts, { desc = "Insert summarize" }))
                    vim.keymap.set("n", "<leader>tb", "itabulate <Esc>a", 
                        vim.tbl_extend("force", opts, { desc = "Insert tabulate" }))
                    vim.keymap.set("n", "<leader>dt", "idescribe <Esc>a", 
                        vim.tbl_extend("force", opts, { desc = "Insert describe" }))
                end
            })
        end,
    },

    -- Markdown preview plugin
    {
        "iamcco/markdown-preview.nvim",
        build = "cd app && npm install",
        ft = "markdown",
        config = function()
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
        end,
    },
}
