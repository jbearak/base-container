#!/usr/bin/env Rscript
# install_packages.R - Direct R implementation of pak-based package installation
# Phase 3 implementation - companion to install_r_packages_pak.sh

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
packages_file <- if (length(args) > 0) args[1] else "R_packages.txt"
debug_mode <- "--debug" %in% args

cat("📦 R Package Installation using pak\n")
cat("=====================================\n")
cat("Packages file:", packages_file, "\n")
cat("Debug mode:", debug_mode, "\n")
cat("Start time:", format(Sys.time()), "\n\n")

start_time <- Sys.time()

# Install pak if not available
if (!requireNamespace("pak", quietly = TRUE)) {
    cat("🔧 Installing pak...\n")
    install.packages("pak", repos = sprintf(
        "https://r-lib.github.io/p/pak/stable/%s/%s/%s", 
        .Platform$pkgType, R.Version()$os, R.Version()$arch
    ))
}

library(pak)

# Function to safely install packages with error handling
safe_install <- function(packages, description = "packages") {
    cat("📦 Installing", description, "...\n")
    
    tryCatch({
        if (debug_mode) {
            cat("Installing:", paste(packages, collapse = ", "), "\n")
        }
        
        pak::pkg_install(packages, dependencies = TRUE)
        cat("✅", description, "installed successfully\n")
        return(TRUE)
        
    }, error = function(e) {
        cat("❌", description, "installation failed:", conditionMessage(e), "\n")
        return(FALSE)
    })
}

# Track installation results
results <- list(
    success = character(0),
    failed = character(0)
)

# Install CRAN packages from file
if (file.exists(packages_file)) {
    cran_packages <- readLines(packages_file)
    cran_packages <- cran_packages[cran_packages != ""]
    
    cat("📋 Found", length(cran_packages), "CRAN packages in", packages_file, "\n")
    
    if (safe_install(cran_packages, paste("CRAN packages from", packages_file))) {
        results$success <- c(results$success, cran_packages)
    } else {
        results$failed <- c(results$failed, cran_packages)
    }
} else {
    cat("⚠️  Package file not found:", packages_file, "\n")
}

# Install special packages
special_packages <- list(
    mcmcplots = "https://cran.r-project.org/src/contrib/Archive/mcmcplots/mcmcplots_0.4.3.tar.gz",
    httpgd = "nx10/httpgd",
    colorout = "jalvesaq/colorout"
)

cat("\n🔧 Installing special packages...\n")

for (pkg_name in names(special_packages)) {
    pkg_spec <- special_packages[[pkg_name]]
    
    description <- switch(pkg_name,
        mcmcplots = "mcmcplots from CRAN archive",
        httpgd = "httpgd from GitHub (nx10/httpgd)",
        colorout = "colorout from GitHub (jalvesaq/colorout)"
    )
    
    if (safe_install(pkg_spec, description)) {
        results$success <- c(results$success, pkg_name)
    } else {
        results$failed <- c(results$failed, pkg_name)
    }
}

# Verification
cat("\n🔍 Verifying installations...\n")
installed_pkgs <- rownames(installed.packages())

# Check CRAN packages
if (file.exists(packages_file)) {
    expected_cran <- readLines(packages_file)
    expected_cran <- expected_cran[expected_cran != ""]
    missing_cran <- setdiff(expected_cran, installed_pkgs)
    
    if (length(missing_cran) > 0) {
        cat("❌ Missing CRAN packages:", paste(missing_cran, collapse = ", "), "\n")
        results$failed <- unique(c(results$failed, missing_cran))
    } else {
        cat("✅ All CRAN packages verified\n")
    }
}

# Check special packages
expected_special <- names(special_packages)
missing_special <- setdiff(expected_special, installed_pkgs)

if (length(missing_special) > 0) {
    cat("❌ Missing special packages:", paste(missing_special, collapse = ", "), "\n")
    results$failed <- unique(c(results$failed, missing_special))
} else {
    cat("✅ All special packages verified\n")
}

# Final summary
end_time <- Sys.time()
duration <- as.numeric(difftime(end_time, start_time, units = "secs"))
minutes <- floor(duration / 60)
seconds <- round(duration %% 60)

success_count <- length(unique(results$success))
failed_count <- length(unique(results$failed))

cat("\n==========================================\n")
cat("📊 R PACKAGE INSTALLATION SUMMARY (pak)\n")
cat("==========================================\n")
cat("   ✅ Successfully installed:", success_count, "packages\n")
cat("   ❌ Failed installations:", failed_count, "packages\n")
cat("   🕒 Total time:", sprintf("%dm %ds", minutes, seconds), "\n")
cat("   📅 End time:", format(end_time), "\n\n")

if (failed_count > 0) {
    cat("❌ FAILED PACKAGES:\n")
    cat("===================\n")
    for (pkg in unique(results$failed)) {
        cat("   •", pkg, "\n")
    }
    cat("\n⚠️  Installation completed with", failed_count, "failed packages.\n")
    cat("    Consider investigating these packages and their system dependencies.\n")
    quit(status = 1)
} else {
    cat("🎉 ALL PACKAGES INSTALLED SUCCESSFULLY!\n")
    cat("   No failed packages to report.\n")
    cat("   pak-based installation completed successfully.\n")
}