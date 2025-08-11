#!/usr/bin/env Rscript
# test_package_validation.R - Comprehensive Package Validation
# Phase 4 implementation for pak migration (Issue #2)
#
# This script performs comprehensive validation of R packages installed via pak,
# including functionality testing, version compatibility, dependency verification,
# and regression testing.

# Load required libraries
suppressPackageStartupMessages({
    library(pak)
    library(jsonlite)
})

# Configuration
args <- commandArgs(trailingOnly = TRUE)
PACKAGES_FILE <- if (length(args) > 0) args[1] else "R_packages.txt"
RESULTS_DIR <- if (length(args) > 1) args[2] else "package_validation_results"
VERBOSE <- "--verbose" %in% args
QUICK_MODE <- "--quick" %in% args
DEEP_VALIDATION <- "--deep" %in% args && !QUICK_MODE

# Create results directory
timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
session_dir <- file.path(RESULTS_DIR, timestamp)
dir.create(session_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(session_dir, "logs"), showWarnings = FALSE)
dir.create(file.path(session_dir, "reports"), showWarnings = FALSE)
dir.create(file.path(session_dir, "metrics"), showWarnings = FALSE)

# Logging functions
log_file <- file.path(session_dir, "validation.log")

log_message <- function(message, level = "INFO") {
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    log_entry <- sprintf("[%s] %s: %s", timestamp, level, message)
    cat(log_entry, "\n")
    cat(log_entry, "\n", file = log_file, append = TRUE)
}

log_info <- function(message) log_message(message, "INFO")
log_success <- function(message) log_message(paste("✅", message), "SUCCESS")
log_warning <- function(message) log_message(paste("⚠️ ", message), "WARNING")
log_error <- function(message) log_message(paste("❌", message), "ERROR")
log_header <- function(message) {
    log_message("", "INFO")
    log_message(message, "HEADER")
    log_message(paste(rep("=", nchar(message)), collapse = ""), "HEADER")
}

# Test result tracking
test_results <- list()
package_metrics <- list()

# Initialize validation environment
init_validation <- function() {
    log_header("🧪 Phase 4: Comprehensive Package Validation")
    log_info(paste("Session:", timestamp))
    log_info(paste("Results directory:", session_dir))
    log_info(paste("Packages file:", PACKAGES_FILE))
    log_info(paste("Quick mode:", QUICK_MODE))
    log_info(paste("Deep validation:", DEEP_VALIDATION))
    
    # System information
    system_info <- list(
        timestamp = timestamp,
        r_version = paste(R.version$major, R.version$minor, sep = "."),
        platform = R.version$platform,
        os = R.version$os,
        pak_version = as.character(packageVersion("pak")),
        library_paths = .libPaths(),
        repos = getOption("repos")
    )
    
    write_json(system_info, file.path(session_dir, "system_info.json"), pretty = TRUE)
    log_success("Validation environment initialized")
}

# Read and parse package list
read_package_list <- function() {
    if (!file.exists(PACKAGES_FILE)) {
        log_error(paste("Package file not found:", PACKAGES_FILE))
        quit(status = 1)
    }
    
    packages <- readLines(PACKAGES_FILE)
    packages <- packages[packages != "" & !grepl("^#", packages)]
    packages <- trimws(packages)
    
    log_info(paste("Read", length(packages), "packages from", PACKAGES_FILE))
    return(packages)
}

# Get installed packages information
get_installed_packages <- function() {
    installed <- as.data.frame(installed.packages(), stringsAsFactors = FALSE)
    log_info(paste("Found", nrow(installed), "installed packages"))
    return(installed)
}

# Test package installation status
test_installation_status <- function(packages) {
    log_header("📦 Testing Package Installation Status")
    
    installed <- get_installed_packages()
    installed_names <- installed$Package
    
    missing_packages <- setdiff(packages, installed_names)
    extra_packages <- setdiff(installed_names, packages)
    
    status_results <- list(
        total_expected = length(packages),
        total_installed = length(installed_names),
        missing_count = length(missing_packages),
        extra_count = length(extra_packages),
        missing_packages = missing_packages,
        extra_packages = head(extra_packages, 20), # Limit for readability
        installation_rate = (length(packages) - length(missing_packages)) / length(packages)
    )
    
    if (length(missing_packages) == 0) {
        log_success("All expected packages are installed")
    } else {
        log_warning(paste("Missing packages:", length(missing_packages)))
        if (VERBOSE) {
            for (pkg in head(missing_packages, 10)) {
                log_info(paste("  Missing:", pkg))
            }
        }
    }
    
    write_json(status_results, file.path(session_dir, "metrics", "installation_status.json"), pretty = TRUE)
    test_results[["installation_status"]] <<- status_results
    
    return(status_results)
}

# Test package loading
test_package_loading <- function(packages) {
    log_header("🔄 Testing Package Loading")
    
    installed <- get_installed_packages()
    installed_names <- installed$Package
    testable_packages <- intersect(packages, installed_names)
    
    if (QUICK_MODE) {
        # Test only a subset in quick mode
        testable_packages <- head(testable_packages, 20)
        log_info(paste("Quick mode: testing", length(testable_packages), "packages"))
    }
    
    loading_results <- list()
    successful_loads <- 0
    failed_loads <- 0
    
    for (pkg in testable_packages) {
        if (VERBOSE) log_info(paste("Testing load:", pkg))
        
        start_time <- Sys.time()
        load_result <- tryCatch({
            # Detach package if already loaded
            if (paste0("package:", pkg) %in% search()) {
                detach(paste0("package:", pkg), character.only = TRUE, unload = TRUE)
            }
            
            # Try to load the package
            library(pkg, character.only = TRUE, quietly = !VERBOSE)
            
            # Get basic package info
            pkg_info <- list(
                success = TRUE,
                version = as.character(packageVersion(pkg)),
                load_time = as.numeric(difftime(Sys.time(), start_time, units = "secs")),
                namespace_loaded = isNamespaceLoaded(pkg),
                error = NULL
            )
            
            successful_loads <<- successful_loads + 1
            if (VERBOSE) log_success(paste("Loaded:", pkg))
            
            pkg_info
        }, error = function(e) {
            failed_loads <<- failed_loads + 1
            error_msg <- conditionMessage(e)
            log_error(paste("Failed to load", pkg, ":", error_msg))
            
            list(
                success = FALSE,
                version = NA,
                load_time = as.numeric(difftime(Sys.time(), start_time, units = "secs")),
                namespace_loaded = FALSE,
                error = error_msg
            )
        })
        
        loading_results[[pkg]] <- load_result
    }
    
    loading_summary <- list(
        total_tested = length(testable_packages),
        successful_loads = successful_loads,
        failed_loads = failed_loads,
        success_rate = successful_loads / length(testable_packages),
        results = loading_results
    )
    
    log_success(paste("Package loading:", successful_loads, "/", length(testable_packages), "successful"))
    
    write_json(loading_summary, file.path(session_dir, "metrics", "loading_results.json"), pretty = TRUE)
    test_results[["loading"]] <<- loading_summary
    
    return(loading_summary)
}

# Test package functionality (basic smoke tests)
test_package_functionality <- function(packages) {
    if (!DEEP_VALIDATION) {
        log_info("Skipping functionality tests (not in deep validation mode)")
        return(NULL)
    }
    
    log_header("🔧 Testing Package Functionality")
    
    # Define basic functionality tests for common packages
    functionality_tests <- list(
        "dplyr" = function() {
            data.frame(x = 1:3, y = 4:6) %>% 
                dplyr::filter(x > 1) %>% 
                dplyr::mutate(z = x + y) %>%
                nrow() == 2
        },
        "ggplot2" = function() {
            p <- ggplot2::ggplot(data.frame(x = 1:3, y = 1:3), ggplot2::aes(x, y)) + 
                 ggplot2::geom_point()
            inherits(p, "ggplot")
        },
        "readr" = function() {
            temp_file <- tempfile(fileext = ".csv")
            readr::write_csv(data.frame(a = 1:3, b = 4:6), temp_file)
            result <- readr::read_csv(temp_file, show_col_types = FALSE)
            unlink(temp_file)
            nrow(result) == 3
        },
        "stringr" = function() {
            stringr::str_detect("hello world", "world")
        },
        "lubridate" = function() {
            date_obj <- lubridate::ymd("2023-01-01")
            lubridate::year(date_obj) == 2023
        }
    )
    
    installed <- get_installed_packages()
    installed_names <- installed$Package
    testable_packages <- intersect(names(functionality_tests), installed_names)
    
    functionality_results <- list()
    successful_tests <- 0
    failed_tests <- 0
    
    for (pkg in testable_packages) {
        log_info(paste("Testing functionality:", pkg))
        
        test_result <- tryCatch({
            # Ensure package is loaded
            library(pkg, character.only = TRUE, quietly = TRUE)
            
            # Run the functionality test
            test_passed <- functionality_tests[[pkg]]()
            
            if (test_passed) {
                successful_tests <<- successful_tests + 1
                log_success(paste("Functionality test passed:", pkg))
            } else {
                failed_tests <<- failed_tests + 1
                log_error(paste("Functionality test failed:", pkg))
            }
            
            list(success = test_passed, error = NULL)
        }, error = function(e) {
            failed_tests <<- failed_tests + 1
            error_msg <- conditionMessage(e)
            log_error(paste("Functionality test error for", pkg, ":", error_msg))
            list(success = FALSE, error = error_msg)
        })
        
        functionality_results[[pkg]] <- test_result
    }
    
    functionality_summary <- list(
        total_tested = length(testable_packages),
        successful_tests = successful_tests,
        failed_tests = failed_tests,
        success_rate = if (length(testable_packages) > 0) successful_tests / length(testable_packages) else 0,
        results = functionality_results
    )
    
    log_success(paste("Functionality tests:", successful_tests, "/", length(testable_packages), "passed"))
    
    write_json(functionality_summary, file.path(session_dir, "metrics", "functionality_results.json"), pretty = TRUE)
    test_results[["functionality"]] <<- functionality_summary
    
    return(functionality_summary)
}

# Test dependency resolution
test_dependency_resolution <- function(packages) {
    log_header("🔗 Testing Dependency Resolution")
    
    if (QUICK_MODE) {
        test_packages <- head(packages, 10)
        log_info(paste("Quick mode: testing dependencies for", length(test_packages), "packages"))
    } else {
        test_packages <- packages
    }
    
    dependency_results <- list()
    resolution_errors <- 0
    
    for (pkg in test_packages) {
        if (VERBOSE) log_info(paste("Checking dependencies for:", pkg))
        
        dep_result <- tryCatch({
            deps <- pak::pkg_deps(pkg)
            
            list(
                success = TRUE,
                dependency_count = nrow(deps),
                dependencies = deps$package,
                error = NULL
            )
        }, error = function(e) {
            resolution_errors <<- resolution_errors + 1
            error_msg <- conditionMessage(e)
            log_error(paste("Dependency resolution failed for", pkg, ":", error_msg))
            
            list(
                success = FALSE,
                dependency_count = 0,
                dependencies = character(0),
                error = error_msg
            )
        })
        
        dependency_results[[pkg]] <- dep_result
    }
    
    dependency_summary <- list(
        total_tested = length(test_packages),
        resolution_errors = resolution_errors,
        success_rate = (length(test_packages) - resolution_errors) / length(test_packages),
        results = dependency_results
    )
    
    log_success(paste("Dependency resolution:", length(test_packages) - resolution_errors, "/", length(test_packages), "successful"))
    
    write_json(dependency_summary, file.path(session_dir, "metrics", "dependency_results.json"), pretty = TRUE)
    test_results[["dependencies"]] <<- dependency_summary
    
    return(dependency_summary)
}

# Test version compatibility
test_version_compatibility <- function() {
    log_header("📊 Testing Version Compatibility")
    
    installed <- get_installed_packages()
    
    # Check for version conflicts or issues
    version_issues <- list()
    
    # Check R version compatibility
    r_version <- getRversion()
    min_r_version <- "4.0.0"
    
    if (r_version < min_r_version) {
        version_issues[["r_version"]] <- paste("R version", r_version, "may be too old (minimum:", min_r_version, ")")
    }
    
    # Check for packages with very old versions (potential security issues)
    current_year <- as.numeric(format(Sys.Date(), "%Y"))
    old_packages <- c()
    
    for (i in seq_len(nrow(installed))) {
        pkg_info <- installed[i, ]
        if (!is.na(pkg_info$Built)) {
            built_year <- as.numeric(substr(pkg_info$Built, 1, 4))
            if (current_year - built_year > 3) {
                old_packages <- c(old_packages, pkg_info$Package)
            }
        }
    }
    
    if (length(old_packages) > 0) {
        version_issues[["old_packages"]] <- head(old_packages, 10)
    }
    
    version_summary <- list(
        r_version = as.character(r_version),
        total_packages = nrow(installed),
        old_packages_count = length(old_packages),
        version_issues = version_issues,
        compatibility_score = if (length(version_issues) == 0) 1.0 else max(0, 1 - length(version_issues) * 0.1)
    )
    
    if (length(version_issues) == 0) {
        log_success("No version compatibility issues found")
    } else {
        log_warning(paste("Found", length(version_issues), "version compatibility issues"))
    }
    
    write_json(version_summary, file.path(session_dir, "metrics", "version_compatibility.json"), pretty = TRUE)
    test_results[["version_compatibility"]] <<- version_summary
    
    return(version_summary)
}

# Generate comprehensive validation report
generate_validation_report <- function() {
    log_header("📊 Generating Validation Report")
    
    # Calculate overall scores
    overall_score <- 0
    total_weight <- 0
    
    if ("installation_status" %in% names(test_results)) {
        installation_score <- test_results$installation_status$installation_rate
        overall_score <- overall_score + installation_score * 0.3
        total_weight <- total_weight + 0.3
    }
    
    if ("loading" %in% names(test_results)) {
        loading_score <- test_results$loading$success_rate
        overall_score <- overall_score + loading_score * 0.3
        total_weight <- total_weight + 0.3
    }
    
    if ("functionality" %in% names(test_results)) {
        functionality_score <- test_results$functionality$success_rate
        overall_score <- overall_score + functionality_score * 0.2
        total_weight <- total_weight + 0.2
    }
    
    if ("dependencies" %in% names(test_results)) {
        dependency_score <- test_results$dependencies$success_rate
        overall_score <- overall_score + dependency_score * 0.1
        total_weight <- total_weight + 0.1
    }
    
    if ("version_compatibility" %in% names(test_results)) {
        compatibility_score <- test_results$version_compatibility$compatibility_score
        overall_score <- overall_score + compatibility_score * 0.1
        total_weight <- total_weight + 0.1
    }
    
    if (total_weight > 0) {
        overall_score <- overall_score / total_weight
    }
    
    # Create comprehensive report
    report_summary <- list(
        timestamp = timestamp,
        overall_score = overall_score,
        grade = if (overall_score >= 0.9) "A" else if (overall_score >= 0.8) "B" else if (overall_score >= 0.7) "C" else if (overall_score >= 0.6) "D" else "F",
        test_results = test_results,
        recommendations = list()
    )
    
    # Add recommendations based on results
    if ("installation_status" %in% names(test_results) && test_results$installation_status$missing_count > 0) {
        report_summary$recommendations <- append(report_summary$recommendations, 
            paste("Install", test_results$installation_status$missing_count, "missing packages"))
    }
    
    if ("loading" %in% names(test_results) && test_results$loading$success_rate < 0.9) {
        report_summary$recommendations <- append(report_summary$recommendations,
            "Investigate package loading failures")
    }
    
    if ("functionality" %in% names(test_results) && test_results$functionality$success_rate < 0.8) {
        report_summary$recommendations <- append(report_summary$recommendations,
            "Review functionality test failures")
    }
    
    # Save comprehensive report
    write_json(report_summary, file.path(session_dir, "reports", "validation_report.json"), pretty = TRUE)
    
    # Generate text summary
    summary_file <- file.path(session_dir, "reports", "validation_summary.txt")
    cat("=== Package Validation Report ===\n", file = summary_file)
    cat(paste("Session:", timestamp, "\n"), file = summary_file, append = TRUE)
    cat(paste("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n"), file = summary_file, append = TRUE)
    cat(paste("Overall Score:", sprintf("%.1f%%", overall_score * 100), "\n"), file = summary_file, append = TRUE)
    cat(paste("Grade:", report_summary$grade, "\n"), file = summary_file, append = TRUE)
    cat("\n=== Test Results ===\n", file = summary_file, append = TRUE)
    
    for (test_name in names(test_results)) {
        result <- test_results[[test_name]]
        if ("success_rate" %in% names(result)) {
            cat(paste(test_name, ":", sprintf("%.1f%%", result$success_rate * 100), "\n"), 
                file = summary_file, append = TRUE)
        }
    }
    
    if (length(report_summary$recommendations) > 0) {
        cat("\n=== Recommendations ===\n", file = summary_file, append = TRUE)
        for (rec in report_summary$recommendations) {
            cat(paste("•", rec, "\n"), file = summary_file, append = TRUE)
        }
    }
    
    log_success(paste("Validation report generated:", file.path(session_dir, "reports", "validation_report.json")))
    log_success(paste("Validation summary generated:", summary_file))
    
    # Display summary
    cat("\n")
    cat(readLines(summary_file), sep = "\n")
    
    return(report_summary)
}

# Main execution
main <- function() {
    init_validation()
    
    # Read package list
    packages <- read_package_list()
    
    # Run validation tests
    test_installation_status(packages)
    test_package_loading(packages)
    test_package_functionality(packages)
    test_dependency_resolution(packages)
    test_version_compatibility()
    
    # Generate comprehensive report
    report <- generate_validation_report()
    
    log_header("🎯 Package Validation Complete")
    log_success(paste("Results available in:", session_dir))
    
    # Exit with appropriate code
    if (report$overall_score >= 0.8) {
        log_success("Package validation passed!")
        quit(status = 0)
    } else {
        log_warning("Package validation completed with issues")
        quit(status = 1)
    }
}

# Handle help
if ("--help" %in% args || "-h" %in% args) {
    cat("Package Validation Script\n")
    cat("\n")
    cat("Usage: Rscript test_package_validation.R [packages_file] [results_dir] [options]\n")
    cat("\n")
    cat("Arguments:\n")
    cat("  packages_file    Path to package list file (default: R_packages.txt)\n")
    cat("  results_dir      Results directory (default: package_validation_results)\n")
    cat("\n")
    cat("Options:\n")
    cat("  --help, -h       Show this help message\n")
    cat("  --verbose        Enable verbose output\n")
    cat("  --quick          Quick mode (test subset of packages)\n")
    cat("  --deep           Deep validation mode (includes functionality tests)\n")
    cat("\n")
    quit(status = 0)
}

# Run main function
main()