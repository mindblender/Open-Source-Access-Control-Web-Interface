#!/bin/bash
# Test script for PayPal IPN endpoint
# Usage: ./test_ipn.sh [email] [amount]

EMAIL=${1:-"admin@example.com"}
AMOUNT=${2:-"50"}
HOST=${3:-"http://localhost:3000"}

echo "Testing IPN endpoint at ${HOST}/ipns"
echo "Email: ${EMAIL}"
echo "Amount: ${AMOUNT}"
echo ""

# Simulate a PayPal IPN POST request
curl -X POST "${HOST}/ipns" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "txn_type=subscr_payment" \
  -d "txn_id=TEST$(date +%s)" \
  -d "payer_email=${EMAIL}" \
  -d "payment_gross=${AMOUNT}" \
  -d "payment_date=$(date '+%H:%M:%S %b %e, %Y PST')" \
  -d "payment_status=Completed" \
  -d "first_name=Test" \
  -d "last_name=User" \
  -d "item_name=Membership" \
  -v

echo ""
echo ""
echo "Check your Rails logs for the IPN processing details:"
echo "  tail -f log/development.log"
echo ""
echo "Then check the database:"
echo "  rails console"
echo "  > Ipn.last"
echo "  > Payment.last"
