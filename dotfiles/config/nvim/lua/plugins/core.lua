-- Core essential plugins
return {
    -- Color scheme
    {
        "catppuccin/nvim",
        name = "catppuccin",
        priority = 1000,
        config = function()
            require("catppuccin").setup({})
            vim.cmd([[colorscheme catppuccin]])
        end,
    },

    -- Treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        lazy = false, -- Keep this loaded early for syntax highlighting
        config = function()
            require("nvim-treesitter.configs").setup({
                ensure_installed = {
                    "lua", "go", "javascript", "typescript", "python", 
                    "bash", "r", "markdown", "yaml", "rnoweb", "json",
                    "tsx", "css", "html", "vim", "regex"
                },
                highlight = { enable = true },
                auto_install = false, -- Don't auto-install to avoid jsx issue
            })
        end,
    },

    -- Language packs
    { "sheerun/vim-polyglot" },

    -- Icons
    { "kyazdani42/nvim-web-devicons" },

    -- Git integration
    {
        "lewis6991/gitsigns.nvim",
        config = function()
            require('gitsigns').setup()
        end,
    },

    {
        "tpope/vim-fugitive",
    },
}
