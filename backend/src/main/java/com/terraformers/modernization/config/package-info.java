/**
 * Runtime configuration contract and key-presence inspection.
 *
 * <p>This package must not expose secret values. It only checks whether required
 * runtime keys are present so deployment validation can distinguish missing
 * configuration from application logic failures.</p>
 */
package com.terraformers.modernization.config;
