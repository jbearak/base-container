-- Telescope and navigation plugins
return {
    -- Telescope dependencies
    { "nvim-lua/popup.nvim" },
    { "nvim-lua/plenary.nvim" },
    
    -- Main telescope plugin
    {
        "nvim-telescope/telescope.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope-fzf-native.nvim",
        },
        config = function()
            local telescope = require('telescope')
            local actions = require('telescope.actions')
            local action_state = require('telescope.actions.state')
            
            telescope.setup({
                defaults = {
                    prompt_prefix = "$ ",
                    mappings = {
                        i = {
                            ["<c-a>"] = function() 
                                print(vim.inspect(action_state.get_selected_entry())) 
                            end
                        }        
                    }
                }
            })
            
            -- Load extensions
            telescope.load_extension('fzf')
            
            -- Telescope keybindings
            local builtin = require('telescope.builtin')
            
            -- Current buffer fuzzy find with custom dropdown theme
            vim.keymap.set('n', '<C-_>', function()
                builtin.current_buffer_fuzzy_find({
                    sorting_strategy = "ascending",
                    prompt_position = "top"
                })
            end, { desc = 'Search current buffer' })
            
            -- Custom current buffer search with dropdown theme
            local function curr_buf_search()
                local opt = require('telescope.themes').get_dropdown({height=10, previewer=false})
                builtin.current_buffer_fuzzy_find(opt)
            end
            
            -- Make the function available globally if needed
            _G.telescope_curr_buf_search = curr_buf_search
        end,
    },

    -- Telescope FZF native
    {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
    },

    -- Nvim motions
    {
        "phaazon/hop.nvim",
        config = function()
            require("hop").setup()
        end,
    },
}
