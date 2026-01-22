# Open Source Access Control Web Interface - Codebase Overview

**Last Updated:** 2026-01-22
**Purpose:** This document provides a comprehensive overview of the codebase to accelerate future development sessions by eliminating redundant analysis.

---

## Executive Summary

This is a **legacy Rails 3.2.8 application** (circa 2012) built for managing a hackerspace/makerspace community. It integrates member management, physical door access control via Arduino, payment processing, equipment certifications, and network presence tracking. The application was originally built for HeatSync Labs in Mesa, Arizona.

**Critical Context:**
- Very old Rails version (3.2.8) with known security vulnerabilities
- Ruby 1.9.3 (end of life)
- Not suitable for production without significant security updates
- Deep integration with physical hardware (Arduino door controllers)
- Active use of Paperclip for file uploads to Amazon S3

---

## Technology Stack

### Core Framework
```ruby
# From Gemfile
ruby '1.9.3'
gem 'rails', '3.2.8'
gem 'pg'                    # PostgreSQL (primary database)
gem 'sqlite3'               # Also available
gem 'passenger'             # Application server
```

### Key Dependencies
| Gem | Version | Purpose |
|-----|---------|---------|
| devise | 2.2.7 | User authentication |
| cancan | 1.6.10 | Authorization (CanCan, not CanCanCan) |
| paperclip | ~> 3.0 | File attachments (images, contracts) |
| aws-sdk | latest | Amazon S3 storage |
| rails-settings-cached | 0.2.4 | Application-wide settings |
| gravtastic | latest | Gravatar integration |
| bcrypt-ruby | ~> 3.0.0 | Password hashing |
| jquery-rails | latest | jQuery JavaScript |
| sass-rails | ~> 3.2.3 | SASS stylesheets |
| coffee-rails | ~> 3.2.1 | CoffeeScript |
| dotenv-rails | latest | Environment variables |

### Frontend Stack
- **Views:** ERB templates (Rails 3 standard)
- **CSS Framework:** Bootstrap 3 (loaded from `/public/bootstrap/`)
- **JavaScript:** jQuery + jQuery UJS + CoffeeScript
- **Asset Pipeline:** Sprockets (enabled)
- **Icons:** Custom member status icons (coin images)
- **No modern JS frameworks** - vanilla jQuery only

---

## Application Purpose & Features

### What This App Does

This is a **member management system for hackerspaces/makerspaces** that:

1. **Member Management**
   - User accounts with profiles, emergency contacts, skills
   - Member levels: Volunteer, Associate ($25), Basic ($50), Plus ($100)
   - Orientation tracking and waiver management
   - User merging capability for duplicate accounts

2. **Physical Access Control**
   - RFID card management
   - Integration with Arduino door controller (via HTTP)
   - Remote door access (unlock, lock, open, arm/disarm)
   - Access logging and statistics
   - Card permission levels (0 = no access, 1 = full access)

3. **Payment Processing**
   - PayPal IPN (Instant Payment Notification) webhook
   - PayPal CSV import
   - Payment history tracking
   - Delinquency calculation and member status updates

4. **Equipment Certifications**
   - Training/certification tracking (e.g., "laser-cutter")
   - User-to-certification linking
   - Interlock integration (API for equipment to check authorization)

5. **Network Presence Tracking**
   - MAC address scanning via `arp-scan`
   - "Who's at the space" feature
   - Active/inactive device tracking
   - Presence statistics and history

6. **Resource Inventory**
   - Tool/equipment database with photos
   - Ownership tracking
   - Categories and disposal tracking
   - S3-stored images via Paperclip

7. **Space API**
   - Public JSON API for door status
   - Implements Space API standard (hackerspace.org)
   - Remote access interface with authentication

---

## Directory Structure

```
/home/user/Open-Source-Access-Control-Web-Interface/
├── app/
│   ├── assets/
│   │   ├── javascripts/      # CoffeeScript files per controller
│   │   └── stylesheets/      # SCSS files
│   ├── controllers/          # 18 controllers
│   ├── helpers/              # View helpers
│   ├── mailers/              # UserMailer, DoorMailer
│   ├── models/               # 16 ActiveRecord models
│   │   └── ability.rb        # CanCan authorization
│   └── views/                # ERB templates
├── config/
│   ├── environments/         # development.rb, production.rb, test.rb
│   ├── initializers/         # Devise, settings, load_config
│   ├── application.rb        # Main config (timezone: America/Phoenix)
│   ├── routes.rb             # Route definitions
│   ├── config.yml.example    # SMTP & door access credentials
│   └── database.yml.example  # PostgreSQL config
├── db/
│   ├── migrate/              # 52 migrations (dating back to 2012)
│   ├── schema.rb             # Current database schema
│   └── seeds.rb              # Default admin user
├── lib/                      # Custom libraries
├── public/
│   └── bootstrap/            # Bootstrap 3 CSS/JS
├── test/                     # Empty test structure
├── vendor/                   # Third-party code
├── Dockerfile                # Docker support
├── docker-compose.yml        # Docker Compose config
├── Gemfile & Gemfile.lock
└── README.md
```

---

## Database Schema Overview

**Database:** PostgreSQL
**Schema Version:** 20141120200638
**Migrations:** 52 total

### Core Tables

#### users
Primary member table with Devise fields:
- **Core:** id, email, name, encrypted_password
- **Devise:** reset_password_token, remember_created_at, sign_in_count, etc.
- **Member Info:** member_level, payment_method, orientation, waiver
- **Emergency:** emergency_name, emergency_phone, emergency_email, phone
- **Skills:** current_skills, desired_skills
- **Social:** twitter_url, facebook_url, github_url, website_url
- **Admin Flags:** admin, instructor, accountant, hidden
- **Relationships:** oriented_by_id (self-referential)
- **Marketing:** marketing_source, payee, postal_code
- **Visibility:** email_visible, phone_visible

#### cards
RFID access cards:
- card_number (RFID string)
- card_permissions (0 or 1)
- user_id (belongs to user)
- name (card nickname)

#### certifications
Equipment training types:
- name, description, slug
- Examples: "laser-cutter", "wood-shop"

#### user_certifications (join table)
- user_id, certification_id
- created_by, updated_by (audit trail)

#### payments
Payment records:
- user_id, date, amount
- Links to ipn or paypal_csv

#### ipns (PayPal IPN data)
- payment_id, txn_id, txn_type
- payer_email, payer_id, payment_gross
- Full PayPal IPN data stored

#### paypal_csvs
- payment_id, data (CSV row)

#### contracts
Signed liability waivers:
- user_id, created_by_id
- first_name, last_name, signed_at, cosigner
- Paperclip fields: document_file_name, document_content_type, etc.
- Stored on S3

#### resources
Tool/equipment inventory:
- user_id (owner), resource_category_id
- name, serial, specs, status, estimated_value
- Paperclip fields: picture_file_name, etc.
- disposed_at (soft delete)

#### macs
Network MAC addresses:
- user_id, mac, ip
- active (boolean), since, refreshed
- hidden, note

#### mac_logs
Network presence events:
- mac, ip, action ('activate' or 'deactivate')

#### door_logs
Physical access logs:
- key (event type: 'G'=Granted, 'D'=Denied, 'C'=Command, etc.)
- data (card number or command result)
- Indexed on created_at and key

#### settings
Application-wide settings (rails-settings-cached):
- var (setting name), value (serialized)

---

## Key Models & Relationships

### User Model (`app/models/user.rb`)

**Central model** of the application.

**Relationships:**
```ruby
belongs_to :oriented_by, class_name: "User"
has_many :cards
has_many :user_certifications
has_many :certifications, through: :user_certifications
has_many :contracts
has_many :payments
has_many :macs
has_many :resources
```

**Scopes:**
```ruby
scope :volunteer, -> { where('member_level >= 10 AND member_level < 25') }
scope :active, -> { where('member_level >= 10') }
scope :paying, -> { joins(:payments).where("payments.date > ?", (DateTime.now - 90.days)).uniq }
```

**Member Levels:**
```ruby
0-9:     Not a member
10-24:   Volunteer (shows heart icon)
25-49:   Associate ($25/month, copper coin)
50-99:   Basic ($50/month, silver coin)
100-999: Plus ($100/month, gold coin)
```

**Key Methods:**
- `card_access_enabled` - Has at least one card with permission level 1
- `member_status` - Returns rank based on level + payment status
- `member_status_symbol` - Returns HTML img tag with coin icon
- `payment_status` - Checks if payments are current (60-day window)
- `delinquency` - Days since last payment
- `absorb_user(user)` - Merges another user's data (cards, certs, payments)
- `has_certification?(slug)` - Check if user has specific certification
- `send_email(from, subject, body)` - Send email via UserMailer

**Payment Status Logic:**
- Paid if last payment within 60 days
- Delinquent if > 60 days
- Member status rank reduced by 10x if delinquent

**Validations:**
```ruby
validates_presence_of [:name, :postal_code, :current_skills, :desired_skills, :marketing_source]
validates_format_of [:twitter_url, :facebook_url, :github_url, :website_url], with: URI::regexp
validates_format_of :email, without: /\.ru$/ # Blocks .ru emails
```

**Callbacks:**
```ruby
after_create :send_new_user_email
```

### Card Model
```ruby
belongs_to :user
# Fields: card_number, card_permissions, name
```

**Upload to Arduino:**
- Format: `?m{card_id}&p{permissions}&t{card_number}&e={password}`
- Sent via HTTP to configured door_access_url

### Certification & UserCertification
```ruby
# Certification
has_many :user_certifications
has_many :users, through: :user_certifications

# UserCertification (join table)
belongs_to :user
belongs_to :certification
# Audit: created_by, updated_by
```

### Payment, Ipn, PaypalCsv
```ruby
# Payment
belongs_to :user
has_one :ipn
has_one :paypal_csv

# Ipn
belongs_to :payment
# Stores full PayPal IPN data

# PaypalCsv
belongs_to :payment
# Stores CSV row data
```

### Contract
```ruby
belongs_to :user
belongs_to :created_by, class_name: "User"
has_attached_file :document # Paperclip (S3)
```

### Resource & ResourceCategory
```ruby
# Resource
belongs_to :user
belongs_to :resource_category
has_attached_file :picture # Paperclip (S3)

# ResourceCategory
has_many :resources
```

### Mac & MacLog
```ruby
# Mac
belongs_to :user
# Fields: mac, ip, active, since, refreshed, hidden, note

# MacLog
# Fields: mac, ip, action ('activate'/'deactivate')
```

### DoorLog
```ruby
# No associations
# Fields: key, data
# Keys: 'G'=Granted, 'D'=Denied, 'C'=Command, etc.
```

---

## Authorization System (CanCan)

**File:** `app/models/ability.rb`

### Permission Levels (in order):

1. **Anonymous (not logged in):**
   - Read: Mac, Resource, ResourceCategory
   - Can scan Macs (for CRON)

2. **Logged-in users:**
   - Read/update own: Cards, Payments, UserCertifications
   - Read: All Certifications
   - Create/update own Macs
   - Create/update/destroy own Resources
   - Compose and send emails

3. **Card holders** (`card_access_enabled == true`):
   - `can :access_doors_remotely, :door_access`
   - `can :authorize, Card` (for interlock API)

4. **Oriented users** (`orientation` not blank):
   - Read: All non-hidden Users
   - Read: All UserCertifications
   - View activity reports
   - Create/update Resources (even unowned)
   - Create/update/destroy ResourceCategories

5. **Instructors** (`instructor == true`):
   - Manage: Certifications
   - Create/read: Non-hidden Users
   - Create/read UserCertifications
   - Update/destroy own UserCertifications

6. **Accountants** (`accountant == true`):
   - Manage: Payment, Ipn, PaypalCsv

7. **Admins** (`admin == true`):
   - `can :manage, :all`

### Restrictions (apply to everyone except admins):
```ruby
cannot :destroy, Certification
cannot :destroy, Mac
cannot :destroy, MacLog
cannot :destroy, DoorLog
```

---

## Routes & Controllers

**File:** `config/routes.rb`

### Main Routes

#### Home
```ruby
root :to => "home#index"
match 'more_info' => 'home#more_info'
```

#### Users
```ruby
resources :users
match 'user_summary/:id' => 'users#user_summary'
match 'users/activity' => 'users#activity'
match 'users/new_member_report' => 'users#new_member_report'
match 'users/merge' => 'users#merge_view', :via => :get
match 'users/merge' => 'users#merge_action', :via => :post
match 'users/inactive' => 'users#inactive'
match 'users/create' => 'users#create', :via => :post # Avoid Devise conflict
# Email composition
get 'users/:id/compose_email' => 'users#compose_email'
post 'users/:id/email' => 'users#send_email'
```

#### Cards
```ruby
resources :cards
match 'cards/:id/upload' => 'cards#upload'        # Upload single card
match 'cards/upload_all' => 'cards#upload_all'    # Upload all cards
match 'cards/authorize/:id' => 'cards#authorize'  # Interlock API
```

#### Space API
```ruby
match 'space_api' => 'space_api#index'
match 'space_api/simple(.format)' => 'space_api#simple'
match 'space_api/alert_if_not/:status' => 'space_api#alert_if_not_status'
match 'space_api/access' => 'space_api#access', :via => :get
match 'space_api/access' => 'space_api#access_post', :via => :post
```

#### Door Logs
```ruby
match 'door_logs' => 'door_logs#index'
match 'door_logs/download' => 'door_logs#download'       # Manual download
match 'door_logs/auto_download' => 'door_logs#auto_download' # CRON endpoint
```

#### MACs
```ruby
resources :macs
match 'macs/scan' => 'macs#scan'        # Trigger arp-scan
match 'macs/import' => 'macs#import'    # Import from CSV
match 'macs/history' => 'macs#history'  # Activity history
```

#### Payments
```ruby
resources :payments
resources :ipns
match 'ipns/import' => 'ipns#import'
match 'ipns/:id/link' => 'ipns#link'
match 'ipns/:id/validate' => 'ipns#validate'

resources :paypal_csvs
match 'paypal_csvs/:id/link' => 'paypal_csvs#link'
```

#### Certifications
```ruby
resources :certifications
resources :user_certifications
```

#### Contracts & Resources
```ruby
resources :contracts
match 'contracts/find_for_user/:user_id' => 'contracts#find_for_user'

resources :resources
resources :resource_categories, except: :show
```

#### Statistics
```ruby
match 'statistics' => 'statistics#index'
match 'statistics/mac_log' => 'statistics#mac_log'
match 'statistics/door_log' => 'statistics#door_log'
```

#### Settings
```ruby
resources :settings, :only => [:index, :edit, :update]
```

#### Devise (Authentication)
```ruby
devise_for :users, :skip => :registrations
devise_scope :user do
  resource :registration,
    :only => [:new, :create, :edit, :update],
    :path => 'users',
    :path_names => { :new => 'sign_up' },
    :controller => 'registrations',
    :as => :user_registration
end
```
Note: Registration is controlled - users must be created by admins/instructors.

---

## Configuration Files

### config/application.rb
```ruby
config.time_zone = 'America/Phoenix'
config.encoding = "utf-8"
config.filter_parameters += [:password, :pass]
config.active_record.whitelist_attributes = true  # Rails 3 mass assignment protection
config.assets.enabled = true
```

### config/config.yml.example
```yaml
door_access_url: "http://192.168.1.100"  # Arduino controller URL
door_access_password: "password"
smtp:
  address: smtp.gmail.com
  port: 587
  domain: example.com
  user_name: user@gmail.com
  password: password
  authentication: plain
  enable_starttls_auto: true
```

### .env.example
```bash
S3_KEY=your_s3_access_key
S3_SECRET=your_s3_secret
S3_BUCKET=your_bucket_name
```

### db/seeds.rb
```ruby
User.create!(
  name: "Admin User",
  email: "admin@example.com",
  password: "password",
  password_confirmation: "password",
  admin: true,
  member_level: 100
)
```
**⚠️ SECURITY:** Change default password in production!

---

## Hardware Integration

### Arduino Door Controller

**Communication:** HTTP requests to `door_access_url` (configured in config.yml)

#### Uploading Cards
**Single Card Upload:**
```
GET {door_access_url}/?m{card.id}&p{permissions}&t{card_number}&e={password}
```
Example: `http://192.168.1.100/?m1&p1&t1234567890&e=password`

**Bulk Upload:**
Iterates through all cards and uploads each one.

#### Door Commands
Sent via SpaceApiController:
- `unlock` - Unlock door temporarily
- `lock` - Lock door
- `open` - Open door momentarily
- `arm` - Arm alarm
- `disarm` - Disarm alarm

**Command format:**
```
GET {door_access_url}/?command={command}&password={password}
```

#### Downloading Logs
```
GET {door_access_url}/?getlogs&password={password}
```
Returns CSV-like data parsed into DoorLog records.

**Log Keys:**
- `G` = Granted (successful access)
- `D` = Denied (failed access)
- `C` = Command executed
- `A` = Alarm event

### Network Scanning (arp-scan)

**Tool:** `arp-scan` command-line utility

**Usage in MacsController:**
```ruby
# Scan local network for MAC addresses
`arp-scan -l -q`
```

Parses output to create/update Mac records, triggers activate/deactivate MacLog events.

**CRON Job:**
Periodically calls `/macs/scan` to keep "who's at the space" current.

---

## Payment Processing

### PayPal IPN (Instant Payment Notification)

**Endpoint:** `/ipns` (POST from PayPal webhook)

**Process:**
1. PayPal sends IPN data to webhook
2. IPN record created with txn_id, payer_email, payment_gross, etc.
3. Admin links IPN to user account (by email matching)
4. Payment record auto-created when linked
5. Updates user's payment status and member level

### PayPal CSV Import

**Endpoint:** `/paypal_csvs/import`

**Process:**
1. Admin uploads CSV from PayPal account
2. Each row creates a PaypalCsv record
3. Admin links rows to users (by email or "payee" field)
4. Payment records auto-created when linked

**Auto-linking logic:**
- Matches payer_email to user.email
- Matches "payee" field if present
- Manual linking available for edge cases

---

## Frontend Details

### Layout & Views

**Main Layout:** `app/views/layouts/resources.html.erb`
- Bootstrap 3 navigation with dropdown menus
- Responsive design
- Flash message display
- Footer with analytics code injection

**Other Layouts:**
- `application.html.erb` - Minimal layout
- `space_api.html.erb` - Public API layout

### Bootstrap 3 Integration

**Location:** `/public/bootstrap/`
- CSS: bootstrap.min.css, bootstrap-theme.min.css
- JS: bootstrap.min.js
- Loaded directly (not via asset pipeline for this old version)

### Asset Pipeline

**JavaScript:**
- `application.js` manifest
- CoffeeScript files per controller
- jQuery and jQuery UJS

**CSS:**
- `application.css` manifest
- SCSS files for custom styling
- Member status icons (coin images)

### Member Status Symbols

Visual indicators for member levels:
- **Gold coin:** Plus member ($100), current on payments
- **Silver coin:** Basic member ($50), current on payments
- **Copper coin:** Associate member ($25), current on payments
- **Heart:** Volunteer
- **Timeout icon:** Former member
- **No icon:** Not a member

Delinquent members show un-"paid" version of their coin.

---

## API Endpoints

### Space API (Public)

**Standard:** https://spaceapi.io/

**Endpoint:** `/space_api` (GET)
Returns JSON with:
- Space info (name, URL, logo)
- State (open/closed)
- Contact info
- Sensors (door status, etc.)

**Simple Endpoint:** `/space_api/simple.json`
Minimal JSON for quick status checks.

### Remote Access API

**Endpoint:** `/space_api/access` (GET or POST)

**Authentication:** User credentials (email/password) or API token

**Commands:**
- `unlock` - Unlock door
- `lock` - Lock door
- `open` - Open door momentarily
- `arm` - Arm alarm
- `disarm` - Disarm alarm

**Authorization:** Requires `can :access_doors_remotely` (card permission level 1)

### Interlock Authorization API

**Endpoint:** `/cards/authorize/:id` (GET)

**Purpose:** Equipment/tools can check if user+certification is valid

**Parameters:**
- `id` - Card number
- `certification` - Certification slug (optional)

**Returns:** 200 OK if authorized, 403 if not

**Use Case:** Laser cutter checks if card holder has "laser-cutter" certification before operating.

---

## Notable Code Patterns & Quirks

### 1. Rails 3 Legacy Patterns

**Mass Assignment Protection:**
```ruby
# In models
attr_accessible :email, :name, :password, ...
```
Replaced by strong parameters in Rails 4+.

**Routes:**
```ruby
match 'path' => 'controller#action'
```
Should be `get` or `post` in Rails 4+.

### 2. User Merging System

**Method:** `User#absorb_user(user_to_absorb)`

Merges duplicate accounts by:
1. Copying non-blank attributes from source to destination
2. Transferring all cards
3. Transferring all user_certifications
4. Transferring all payments
5. Destroying source user

**Preserves audit trail** via created_by/updated_by fields.

### 3. Orientation Requirement

**Enforcement:** `ApplicationController#check_orientation`

Most features blocked until user is oriented:
- Orientation field must not be blank
- Error message: "You must be oriented before you can view this page"
- Tracks who oriented each user (oriented_by_id)

### 4. Custom Extensions

**File:** `config/initializers/fixnum.rb`
```ruby
class Fixnum
  def fit(min, max)
    # Ensures number is within range
  end
end
```

### 5. Settings System

**Gem:** rails-settings-cached

**Usage:**
```ruby
Setting.welcome_text
Setting.space_api_json
Setting.analytics_code
```

**Default Settings:** `config/initializers/default_settings.rb`

### 6. Email System

**Mailers:**
- `UserMailer` - New user notifications, general emails
- `DoorMailer` - Door status alerts

**Configuration:** Uses APP_CONFIG loaded from config.yml

### 7. Paperclip File Uploads

**Models with attachments:**
- **Contract:** `:document` (PDF waivers)
- **Resource:** `:picture` (tool photos)

**Storage:** Amazon S3 (configured via .env)

**Migration to ActiveStorage recommended** for Rails 5+.

### 8. Security Considerations

**Known Issues:**
- Rails 3.2.8 has numerous CVEs
- Ruby 1.9.3 is end-of-life
- Devise 2.2.7 is very outdated
- CanCan is abandoned (replaced by CanCanCan)
- Default admin password in seeds.rb
- SSL verification disabled in some HTTP calls
- .ru emails blocked (anti-spam measure)

**SSL Enforcement:**
```ruby
# In ApplicationController
force_ssl except: [:some_public_api]
```

### 9. Testing

**Status:** Test directory structure exists but tests are not implemented.

**Directory:** `/test/`
- fixtures/
- functional/
- unit/

**Recommendation:** Add RSpec or Minitest coverage before major refactoring.

---

## Common Workflows

### Adding a New Member

1. Admin creates user account (`/users/new`)
2. User fills out profile (skills, emergency contact)
3. User signs waiver (contract uploaded)
4. Admin marks user as oriented
5. Admin assigns RFID card
6. Card uploaded to Arduino controller
7. User can now access door and all features

### Processing Payments

**Via IPN:**
1. Member pays via PayPal Subscribe button
2. PayPal sends IPN to webhook
3. IPN record created
4. Admin links IPN to user (or auto-links by email)
5. Payment record created
6. Member status updated

**Via CSV:**
1. Admin downloads CSV from PayPal
2. Admin uploads CSV (`/paypal_csvs`)
3. Admin links each row to users
4. Payment records created

### Granting Equipment Certification

1. Instructor trains user on equipment
2. Instructor creates certification if not exists (`/certifications`)
3. Instructor adds user_certification (`/user_certifications/new`)
4. User can now access equipment (if interlock checks API)

### Remote Door Access

1. User has card with permission level 1
2. User navigates to `/space_api/access`
3. User authenticates with email/password
4. User clicks "Unlock" or "Open"
5. App sends HTTP command to Arduino
6. Door unlocks

### Network Presence Tracking

1. CRON job calls `/macs/scan` every 5 minutes
2. App runs `arp-scan -l -q`
3. MACs found are marked active, others inactive
4. MacLog events created for activate/deactivate
5. "Who's at the space" page shows active users

---

## Deployment & Operations

### Docker Setup (Development)

```bash
docker compose up
docker exec -it members_web rake db:setup
# Default login: admin@example.com / password
```

**Database:** Persisted in `db_data` volume

**Access:** `postgres://postgres:postgres@localhost:5432/members_db_development`

### Manual Setup

**Dependencies:**
- Ruby 1.9.3
- PostgreSQL
- Imagemagick (for Paperclip)
- arp-scan (for MAC scanning)

**Steps:**
```bash
bundle install
cp config/config.yml.example config/config.yml
cp config/database.yml.example config/database.yml
cp env.example .env
cp config/initializers/secret_token.rb.example config/initializers/secret_token.rb
# Edit configs as needed
rake db:create
rake db:migrate
rake db:seed
rails server
```

### CRON Jobs

**Door Log Download:**
```bash
*/15 * * * * curl https://yourdomain.com/door_logs/auto_download
```

**MAC Scan:**
```bash
*/5 * * * * curl https://yourdomain.com/macs/scan
```

### Production Considerations

**DO NOT deploy this app to production without:**
1. Upgrading Rails to at least 6.1 or 7.x
2. Upgrading Ruby to at least 2.7 or 3.x
3. Updating all gems (especially Devise, CanCan → CanCanCan)
4. Replacing Paperclip with ActiveStorage
5. Adding comprehensive test coverage
6. Security audit and penetration testing
7. Changing default admin password
8. Reviewing all SSL/TLS configurations

---

## Modernization Roadmap (If Needed)

### Priority 1: Security Updates
- [ ] Upgrade to Rails 7.x
- [ ] Upgrade to Ruby 3.x
- [ ] Replace CanCan with CanCanCan
- [ ] Update Devise to latest
- [ ] Replace Paperclip with ActiveStorage
- [ ] Add Content Security Policy headers
- [ ] Enable CSRF protection everywhere

### Priority 2: Code Modernization
- [ ] Replace `attr_accessible` with strong parameters
- [ ] Replace `match` routes with `get`/`post`/etc.
- [ ] Add RSpec test coverage
- [ ] Extract business logic from controllers to service objects
- [ ] Add background job processing (Sidekiq) for slow operations

### Priority 3: Feature Improvements
- [ ] Add Stripe integration (more reliable than PayPal IPN)
- [ ] Implement proper API versioning
- [ ] Add GraphQL API
- [ ] Modernize frontend (React or Vue)
- [ ] Add real-time updates (ActionCable)
- [ ] Improve mobile responsiveness

### Priority 4: Infrastructure
- [ ] Add CI/CD pipeline
- [ ] Containerize for production (Kubernetes)
- [ ] Add monitoring (Sentry, New Relic)
- [ ] Add logging (Loggly, Papertrail)
- [ ] Database backups and disaster recovery

---

## Quick Reference

### Important Files to Check First

1. **Models:** `app/models/user.rb`, `app/models/ability.rb`
2. **Routes:** `config/routes.rb`
3. **Config:** `config/application.rb`, `config/config.yml.example`
4. **Schema:** `db/schema.rb`
5. **Controllers:** `app/controllers/users_controller.rb`, `app/controllers/space_api_controller.rb`

### Key Concepts to Remember

- **Member levels** are numeric (0-999) not enums
- **Payment status** is calculated on-the-fly (60-day window)
- **Orientation** is required for most features
- **Card permissions** are binary (0 or 1)
- **Arduino integration** is via plain HTTP (no REST)
- **Paperclip** stores files on S3 (requires AWS credentials)

### Common Gotchas

1. **Devise routes conflict:** Users created via POST `/users/create` not POST `/users`
2. **Mass assignment:** Must add fields to `attr_accessible` in model
3. **CanCan syntax:** Uses `can`, `cannot` (not `can?` in ability.rb)
4. **Timezone:** Hard-coded to America/Phoenix
5. **SSL enforcement:** May interfere with local development
6. **arp-scan:** Requires root/sudo permissions
7. **.ru emails:** Blocked by validation (anti-spam)

---

## Questions to Ask Before Starting Work

1. **Is this for production or historical reference?**
   - If production → Recommend upgrading Rails first
   - If reference → Proceed with caution

2. **Is the Arduino hardware still in use?**
   - If yes → Preserve door_access integration
   - If no → Can remove door-related code

3. **What's the deployment target?**
   - Docker → Use existing docker-compose.yml
   - Heroku → Will need significant changes
   - VPS → Document Passenger/nginx setup

4. **Are there any custom forks of this code?**
   - Check git history for organization-specific changes
   - May have undocumented features

5. **What's the current user count and data volume?**
   - Small → Simple migration path
   - Large → Need careful data migration planning

---

## Conclusion

This is a **functional but outdated** Rails application with deep hardware integration. It serves its purpose for hackerspace management but should not be deployed to production without significant security updates.

The codebase is well-structured for Rails 3 standards and demonstrates good separation of concerns. The main technical debt is the Rails/Ruby version, not code quality.

**Best for:**
- Historical reference
- Learning Rails 3 patterns
- Forking and modernizing for similar use cases

**Not suitable for:**
- Production deployment without upgrades
- Learning modern Rails development
- High-security environments

---

**Original codebase by:** Will Bradley (2012-2024)
**License:** Creative Commons Attribution 3.0
**Repository:** https://github.com/zyphlar/Open-Source-Access-Control-Web-Interface
