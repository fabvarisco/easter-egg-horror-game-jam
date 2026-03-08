extends RefCounted
class_name EOSConfig
## EOS Configuration
## Fill in your credentials from Epic Developer Portal
## https://dev.epicgames.com/portal

# ============================================
# CONFIGURE THESE VALUES FROM EPIC DEV PORTAL
# ============================================

const PRODUCT_NAME := "Easter Egg Horror"
const PRODUCT_VERSION := "1.0"

# Get these from: Dev Portal > Your Product > Product Settings
const PRODUCT_ID := "1dadc2ee55b446058d7814253df45124"      # e.g., "abc123def456..."
const SANDBOX_ID := "4cc2372a4b7148cbb553b1b956b90d7a"      # e.g., "abc123def456..."
const DEPLOYMENT_ID := "60a776efe5b74d93b805eef984a7695e"   # e.g., "abc123def456..."

# Get these from: Dev Portal > Your Product > Clients
const CLIENT_ID := "xyza789119bH4jfX88dIoEioAL7IaG91"       # e.g., "xyza1234..."
const CLIENT_SECRET := "8auO0KScuVwZIiVzPsWx7nrIwLScrhySyQ5394vvnOc"   # e.g., "ABCD1234..."

# Encryption key (64 hex characters)
const ENCRYPTION_KEY := "131dec7c91ea0665ad2ef55ed9c513e639d6b3af3cd026edce5949619f725602"

# ============================================

static func get_credentials() -> Dictionary:
	return {
		"product_name": PRODUCT_NAME,
		"product_version": PRODUCT_VERSION,
		"product_id": PRODUCT_ID,
		"sandbox_id": SANDBOX_ID,
		"deployment_id": DEPLOYMENT_ID,
		"client_id": CLIENT_ID,
		"client_secret": CLIENT_SECRET,
		"encryption_key": ENCRYPTION_KEY
	}

static func is_configured() -> bool:
	return PRODUCT_ID != "" and CLIENT_ID != "" and CLIENT_SECRET != ""
