# PayPal IPN (Instant Payment Notification) Setup Guide

## Overview

This application uses PayPal's IPN (Instant Payment Notification) system to automatically update member payment information when payments are received. When properly configured, the system will:

1. **Receive payment notifications** from PayPal automatically
2. **Create IPN records** with all transaction details
3. **Auto-link payments to users** by matching PayPal email to user email/payee
4. **Create payment records** in the database
5. **Update member payment status** automatically

## Recent Fixes (2026-01-22)

✅ Fixed critical bug where `_from_email_address` field was referenced (doesn't exist) - now correctly uses `payer_email`
✅ Added comprehensive logging for debugging
✅ Improved error handling and reporting
✅ Created test script for local testing

---

## How It Works

### Automatic Payment Flow

```
PayPal → IPN Webhook → Your Server (/ipns endpoint)
         ↓
    Create Ipn record
         ↓
    Find matching User (by payer_email)
         ↓
    Validate transaction type (subscr_payment or send_money)
         ↓
    Validate payment amount matches member level
         ↓
    Create Payment record linked to User
         ↓
    Update user's last payment date & status
```

### User Matching Logic

The system tries to find users in this order:
1. Match PayPal `payer_email` to `User.email` (case-insensitive)
2. If not found, match `payer_email` to `User.payee` field (case-insensitive)

### Valid Payment Types

Only these transaction types create payments:
- `subscr_payment` - Recurring subscription payment
- `send_money` - One-time payment

### Valid Payment Amounts

Payment amounts must match defined member levels:
- **$20, $25, $35** → Associate member
- **$50, $75, $80** → Basic member
- **$100** → Plus member

---

## Setup Instructions

### 1. Configure Your Server

**Ensure your server is publicly accessible:**
- Must have a public IP or domain name
- PayPal cannot reach `localhost` or internal IPs
- Port 443 (HTTPS) is strongly recommended for production

**Your IPN endpoint URL will be:**
```
https://yourdomain.com/ipns
```

### 2. Configure PayPal IPN

#### Option A: Account-Wide IPN Setting (Recommended)

1. Log into your PayPal business account
2. Go to **Settings** (gear icon) → **Account Settings**
3. Click **Notifications** in the left sidebar
4. Under **Instant payment notifications**, click **Update**
5. Click **Choose IPN Settings**
6. Enter your notification URL:
   ```
   https://yourdomain.com/ipns
   ```
7. Select **Receive IPN messages (Enabled)**
8. Click **Save**

#### Option B: Per-Button IPN Setting

When creating a payment button or subscription button:
1. In the button creation wizard, look for **Advanced Features**
2. Find the **IPN notification URL** field
3. Enter: `https://yourdomain.com/ipns`
4. Save the button

#### Option C: PayPal API IPN Setting

If using PayPal's API for payments, include this parameter:
```
notify_url=https://yourdomain.com/ipns
```

### 3. Test the Integration

#### Local Testing (Before PayPal Configuration)

Use the provided test script:

```bash
# Test with default admin user
./test_ipn.sh admin@example.com 50

# Test with custom user and amount
./test_ipn.sh user@example.com 100 http://localhost:3000
```

Watch the logs to see what happens:
```bash
tail -f log/development.log
```

You should see log entries like:
```
IPN received from PayPal
IPN params: {...}
IPN saved successfully: ID 1, txn_id: TEST123, payer_email: admin@example.com
IPN 1: Attempting to create payment for payer_email: admin@example.com
IPN 1: Found user 1 (Admin User)
IPN 1: Transaction type 'subscr_payment' is valid
IPN 1: Payment amount 50 matches member level
IPN 1: Payment 1 created successfully for user 1
```

Check the database:
```bash
rails console
> Ipn.last
> Payment.last
> User.first.last_payment_date
```

#### Testing with PayPal Sandbox

1. Create a [PayPal Developer account](https://developer.paypal.com/)
2. Create sandbox buyer and seller accounts
3. Set your sandbox IPN URL to: `https://yourdomain.com/ipns`
4. Make a test payment using the sandbox buyer account
5. Check the IPN History in PayPal Sandbox dashboard

#### Testing with PayPal IPN Simulator

1. Go to [PayPal IPN Simulator](https://developer.paypal.com/dashboard/ipnSimulator)
2. Enter your IPN URL: `https://yourdomain.com/ipns`
3. Select transaction type: **Subscription Payment** or **Web Accept**
4. Fill in test data:
   - **Payer email**: Must match a user in your system
   - **Payment gross**: Must match a valid member level (20, 25, 35, 50, 75, 80, or 100)
5. Click **Send IPN**
6. Check your logs and database

---

## Monitoring & Troubleshooting

### Check IPN Receipt

**View all IPNs:**
Visit: `https://yourdomain.com/ipns`
(Requires admin login)

**Check logs:**
```bash
tail -f log/production.log | grep IPN
```

**Database queries:**
```bash
rails console
> Ipn.order('created_at DESC').limit(10).pluck(:id, :txn_id, :payer_email, :payment_gross, :created_at)
> Payment.order('created_at DESC').limit(10)
```

### Common Issues & Solutions

#### Issue: No IPNs Being Received

**Possible causes:**
1. **Server not publicly accessible**
   - Test: `curl https://yourdomain.com/ipns` from an external network
   - Should return HTTP 200 (even with empty response)

2. **PayPal IPN URL not configured**
   - Check PayPal account settings
   - Verify the URL is exactly: `https://yourdomain.com/ipns` (no trailing slash)

3. **Firewall blocking PayPal's IPs**
   - Whitelist PayPal's IPN IP ranges
   - See: https://www.paypal.com/us/smarthelp/article/what-are-the-ip-addresses-for-paypal-servers-ts1056

4. **SSL certificate issues**
   - PayPal requires valid SSL certificates (not self-signed)
   - Use Let's Encrypt for free SSL

**Debugging steps:**
```bash
# Test if your endpoint is reachable
curl -X POST https://yourdomain.com/ipns \
  -d "test=true" \
  -v

# Check Rails logs immediately after
tail -n 50 log/production.log
```

#### Issue: IPNs Received But Payments Not Created

**Check the logs for error messages:**
```bash
grep "Unable to link payment" log/production.log
```

**Common reasons:**

1. **User not found**
   ```
   Unable to link payment. Couldn't find user/payee 'email@example.com'
   ```
   **Solution:** Verify the user exists with that email or has that email in the `payee` field

2. **Invalid transaction type**
   ```
   Unable to link payment. Transaction is a 'subscr_cancel' instead of...
   ```
   **Solution:** Only `subscr_payment` and `send_money` create payments. Cancellations, refunds, etc. are logged but don't create payments.

3. **Invalid payment amount**
   ```
   Unable to link payment. Couldn't find membership level '45'
   ```
   **Solution:** Payment amount must be exactly 20, 25, 35, 50, 75, 80, or 100

4. **Date parsing error**
   ```
   invalid date
   ```
   **Solution:** PayPal date format may have changed. Check the `payment_date` field format.

#### Issue: Payments Created But Member Status Not Updating

**Check payment status calculation:**
```bash
rails console
> user = User.find_by_email('user@example.com')
> user.last_payment_date
> user.payment_status
> user.delinquency
```

**How payment status works:**
- Checks if last payment is within **60 days**
- If yes → member is "Paid"
- If no → member is "Delinquent"

**Check if payments exist:**
```ruby
user.payments.order('date DESC').limit(5)
```

---

## Manual Linking

If auto-linking fails, admins can manually link IPNs:

1. Go to: `https://yourdomain.com/ipns`
2. Find the unlinked IPN
3. Click **Link** button
4. System will attempt to create the payment manually
5. Error messages will display if linking fails

---

## Security Considerations

### IPN Validation (Currently Disabled)

For security, you should enable IPN validation in production. This verifies that IPNs actually came from PayPal.

**To enable:**

Edit `/app/controllers/ipns_controller.rb` line 24-26:

Change from:
```ruby
# Uncomment the lines below to enable validation
#unless @ipn.validate!
#  Rails.logger.error "Unable to validate IPN: #{@ipn.inspect}"
#end
```

To:
```ruby
# Validate with PayPal
unless @ipn.validate!
  Rails.logger.error "Unable to validate IPN: #{@ipn.inspect}"
  # Optionally: don't save invalid IPNs
  # @ipn.destroy
  # render :nothing => true, :status => :bad_request
  # return
end
```

**Note:** Validation requires your server to make a POST request back to PayPal, which may be blocked by firewalls.

### HTTPS Requirement

PayPal **strongly recommends** HTTPS for IPN endpoints. HTTP may work in sandbox but will likely fail in production.

### IP Whitelisting

Consider restricting the `/ipns` endpoint to only accept requests from PayPal's IP ranges:
- See: https://www.paypal.com/us/smarthelp/article/what-are-the-ip-addresses-for-paypal-servers-ts1056

---

## PayPal IPN History

To see if PayPal is successfully sending IPNs:

1. Log into PayPal business account
2. Go to **Settings** → **Notifications**
3. Click **Instant payment notifications** → **Update** → **IPN History**
4. You'll see all IPN attempts, including:
   - ✅ Successfully delivered
   - ❌ Failed deliveries with error messages
   - 🔄 Retried deliveries

**PayPal retry behavior:**
- If IPN delivery fails, PayPal will retry
- Retries happen over ~4 days
- After retries exhausted, you must manually resend or use CSV import

---

## Alternative: PayPal CSV Import

If IPN is not working or you need to import historical payments:

1. Download CSV from PayPal:
   - Log into PayPal → **Activity** → **Statements** → **Custom**
   - Select date range → **Activity Download**
   - Format: **CSV**

2. Import into system:
   - Visit: `https://yourdomain.com/paypal_csvs`
   - Upload the CSV file
   - Manually link each row to users

**Note:** CSV import is manual and does not provide real-time updates.

---

## Testing Checklist

Before going live:

- [ ] Endpoint is publicly accessible (`curl -X POST https://yourdomain.com/ipns`)
- [ ] SSL certificate is valid (not self-signed)
- [ ] PayPal IPN URL is configured in PayPal account
- [ ] Test payment made through PayPal sandbox
- [ ] IPN shows up in database (`Ipn.last`)
- [ ] Payment is auto-created (`Payment.last`)
- [ ] User's last payment date is updated (`User.first.last_payment_date`)
- [ ] Member status reflects payment (`User.first.payment_status`)
- [ ] PayPal IPN History shows successful delivery
- [ ] Logs show successful processing (no errors)

---

## Additional Resources

- **PayPal IPN Documentation:** https://developer.paypal.com/docs/api-basics/notifications/ipn/
- **PayPal IPN Simulator:** https://developer.paypal.com/dashboard/ipnSimulator
- **PayPal Developer Dashboard:** https://developer.paypal.com/dashboard/
- **PayPal IP Addresses:** https://www.paypal.com/us/smarthelp/article/what-are-the-ip-addresses-for-paypal-servers-ts1056

---

## Support

If you encounter issues:

1. **Check the logs first:** `tail -f log/production.log | grep IPN`
2. **Check PayPal IPN History** for delivery errors
3. **Use the test script** to rule out PayPal-side issues
4. **Review this guide's troubleshooting section**
5. **Check the database** to see what data was received

**Files modified for this feature:**
- `app/controllers/ipns_controller.rb` - Handles incoming IPNs
- `app/models/ipn.rb` - IPN model with auto-linking logic
- `app/models/user.rb` - Payment status calculations
- `test_ipn.sh` - Local testing script

Good luck! 🎉
