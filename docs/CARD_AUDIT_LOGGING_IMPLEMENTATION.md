# Card Audit Logging Implementation Plan

**Created:** 2026-01-29
**Status:** Planning
**Author:** Claude (AI Assistant)
**Reviewed By:** [Pending]

---

## Table of Contents

1. [Overview](#overview)
2. [Current State](#current-state)
3. [Requirements Summary](#requirements-summary)
4. [Database Schema Changes](#database-schema-changes)
5. [Model Changes](#model-changes)
6. [Controller Changes](#controller-changes)
7. [View Changes](#view-changes)
8. [Authorization Changes](#authorization-changes)
9. [Migration Strategy](#migration-strategy)
10. [Testing Considerations](#testing-considerations)
11. [Open Questions](#open-questions)

---

## Overview

### Problem Statement

The `cards` table currently uses the `name` field to store notes about a card. This field can be overwritten on each edit, causing loss of valuable historical information about why cards were created, modified, or deactivated.

### Solution

Implement a comprehensive audit logging system for cards that:

1. Tracks who created/modified each card and when
2. Records what specific fields changed (before/after values)
3. Requires a mandatory comment explaining each change
4. Provides an immutable audit trail that survives card deletion
5. Displays the most recent note in the card list view
6. Provides a detailed audit log view accessible via popup/modal

---

## Current State

### Existing `cards` Table Schema

```ruby
create_table "cards", :force => true do |t|
  t.string   "card_number"
  t.integer  "card_permissions"
  t.datetime "created_at",       :null => false
  t.datetime "updated_at",       :null => false
  t.integer  "user_id"
  t.string   "name"              # Currently used for notes (problem field)
end
```

### Current Form Fields

- User (dropdown)
- Card Note (maps to `name` field - **can be overwritten**)
- Card DB ID (editable number field - **should not be editable**)
- Card Number (text)
- Card Permissions (dropdown: Enabled=1 / Disabled=255)

### Current Permissions

- Cards are managed by **admins only** (`can :manage, :all`)
- Regular users can only read their own cards
- Card holders with access can use the interlock authorization API

---

## Requirements Summary

| Requirement | Decision |
|-------------|----------|
| Notes field immutability | Truly immutable - each edit creates new audit entry |
| Existing `name` data | Migrate to initial audit log entry |
| Card list "Note" column | Shows most recent audit log comment |
| Change comment | **Mandatory** on all edits |
| Action types | Auto-detected from changes (Add, Edit, Delete, Note) |
| Field change tracking | Track specific fields that changed (before → after) |
| DB ID field | Read-only on edit, hidden on create |
| Card deletion | Soft delete with audit trail preserved |
| Audit log permissions | Admin only |
| Audit log UI | Modal/popup, show all entries (no pagination) |
| Note-only entries | Supported (add comment without changing card data) |

---

## Database Schema Changes

### New Table: `card_audit_logs`

This table stores the immutable audit trail for all card changes.

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_card_audit_logs.rb

class CreateCardAuditLogs < ActiveRecord::Migration
  def change
    create_table :card_audit_logs do |t|
      t.integer  :card_id,     null: false  # FK to cards (preserved even after deletion)
      t.integer  :user_id,     null: false  # FK to users - who made the change
      t.string   :action,      null: false  # 'create', 'update', 'delete', 'note'
      t.text     :changes_json              # JSON: {"field": {"old": x, "new": y}, ...}
      t.text     :comment,     null: false  # Mandatory explanation
      t.datetime :created_at,  null: false

      # Note: No updated_at - audit logs are immutable
    end

    add_index :card_audit_logs, :card_id
    add_index :card_audit_logs, :user_id
    add_index :card_audit_logs, :created_at
    add_index :card_audit_logs, :action
  end
end
```

#### Field Descriptions

| Field | Type | Purpose |
|-------|------|---------|
| `card_id` | integer | References the card. **Not a FK constraint** to preserve logs after card deletion |
| `user_id` | integer | The admin who made the change |
| `action` | string | One of: `create`, `update`, `delete`, `note` |
| `changes_json` | text | Serialized JSON tracking field-level changes |
| `comment` | text | **Mandatory** explanation from the admin |
| `created_at` | datetime | When the change occurred |

#### Example `changes_json` Values

**Card Creation:**
```json
{
  "card_number": {"old": null, "new": "1234567890"},
  "card_permissions": {"old": null, "new": 1},
  "user_id": {"old": null, "new": 42}
}
```

**Permission Change:**
```json
{
  "card_permissions": {"old": 1, "new": 255}
}
```

**Note-Only Entry:**
```json
{}
```

### Modify Table: `cards`

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_soft_delete_to_cards.rb

class AddSoftDeleteToCards < ActiveRecord::Migration
  def change
    # Add soft delete support
    add_column :cards, :deleted_at, :datetime
    add_index :cards, :deleted_at

    # Optionally rename 'name' to 'legacy_name' for clarity
    # Or remove it entirely after data migration
    # rename_column :cards, :name, :legacy_name
  end
end
```

### Data Migration

```ruby
# db/migrate/YYYYMMDDHHMMSS_migrate_card_names_to_audit_logs.rb

class MigrateCardNamesToAuditLogs < ActiveRecord::Migration
  def up
    # Find a system user or first admin for attribution
    system_user = User.where(admin: true).first

    Card.find_each do |card|
      # Create initial audit entry for existing cards
      CardAuditLog.create!(
        card_id: card.id,
        user_id: system_user&.id || 0,  # 0 = system migration
        action: 'create',
        changes_json: {
          card_number: { old: nil, new: card.card_number },
          card_permissions: { old: nil, new: card.card_permissions },
          user_id: { old: nil, new: card.user_id }
        }.to_json,
        comment: card.name.present? ?
          "[Migrated] #{card.name}" :
          "[Migrated] Initial card setup (no original note)",
        created_at: card.created_at
      )
    end
  end

  def down
    # Cannot reliably reverse - audit logs are intentionally immutable
    raise ActiveRecord::IrreversibleMigration
  end
end
```

---

## Model Changes

### New Model: `CardAuditLog`

```ruby
# app/models/card_audit_log.rb

class CardAuditLog < ActiveRecord::Base
  # Rails 3 mass assignment protection
  attr_accessible :card_id, :user_id, :action, :changes_json, :comment

  # Associations
  belongs_to :card
  belongs_to :user  # The admin who made the change

  # Validations
  validates :card_id, presence: true
  validates :user_id, presence: true
  validates :action, presence: true, inclusion: {
    in: %w[create update delete note],
    message: "must be create, update, delete, or note"
  }
  validates :comment, presence: { message: "is required - please explain this change" }

  # Scopes
  default_scope order('created_at DESC')
  scope :for_card, ->(card_id) { where(card_id: card_id) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_action, ->(action) { where(action: action) }

  # Parse the JSON changes
  def changes_hash
    return {} if changes_json.blank?
    JSON.parse(changes_json)
  rescue JSON::ParserError
    {}
  end

  # Human-readable action label
  def action_label
    case action
    when 'create' then 'Created'
    when 'update' then 'Updated'
    when 'delete' then 'Deleted'
    when 'note'   then 'Note Added'
    else action.titleize
    end
  end

  # Format changes for display
  def formatted_changes
    changes_hash.map do |field, values|
      old_val = values['old'] || '(none)'
      new_val = values['new'] || '(none)'

      # Special formatting for known fields
      case field
      when 'card_permissions'
        old_val = old_val == 1 ? 'Enabled' : 'Disabled' unless old_val == '(none)'
        new_val = new_val == 1 ? 'Enabled' : 'Disabled' unless new_val == '(none)'
      when 'user_id'
        old_val = User.find_by_id(old_val)&.name || old_val unless old_val == '(none)'
        new_val = User.find_by_id(new_val)&.name || new_val unless new_val == '(none)'
      end

      "#{field.titleize}: #{old_val} → #{new_val}"
    end
  end

  # Check if this was just a note (no actual changes)
  def note_only?
    action == 'note' || changes_hash.empty?
  end
end
```

### Modified Model: `Card`

```ruby
# app/models/card.rb

class Card < ActiveRecord::Base
  # Rails 3 mass assignment protection
  # REMOVE :id from attr_accessible if present
  # REMOVE :name if migrating away from it
  attr_accessible :card_number, :card_permissions, :user_id

  # Existing associations
  belongs_to :user

  # New associations
  has_many :card_audit_logs, dependent: :nullify  # Don't destroy logs when card deleted

  # Soft delete scope
  default_scope where(deleted_at: nil)
  scope :with_deleted, unscoped
  scope :only_deleted, unscoped.where('deleted_at IS NOT NULL')

  # Validations (existing)
  validates :card_number, presence: true
  validates :user_id, presence: true

  # Virtual attribute for audit comment (not persisted on card)
  attr_accessor :audit_comment

  # Get the most recent audit log entry
  def latest_audit_log
    card_audit_logs.first  # default_scope orders by created_at DESC
  end

  # Get the most recent comment for display
  def latest_note
    latest_audit_log&.comment
  end

  # Soft delete implementation
  def soft_delete(deleted_by_user, comment)
    transaction do
      # Create deletion audit entry BEFORE soft deleting
      create_audit_log(
        user: deleted_by_user,
        action: 'delete',
        comment: comment,
        changes: {}  # Or capture final state
      )

      # Perform soft delete
      update_column(:deleted_at, Time.current)
    end
  end

  def deleted?
    deleted_at.present?
  end

  # Restore a soft-deleted card
  def restore(restored_by_user, comment)
    transaction do
      update_column(:deleted_at, nil)

      create_audit_log(
        user: restored_by_user,
        action: 'update',
        comment: "[Restored] #{comment}",
        changes: { deleted_at: { old: deleted_at, new: nil } }
      )
    end
  end

  # Create an audit log entry
  def create_audit_log(user:, action:, comment:, changes: nil)
    # If changes not provided, calculate from model changes
    if changes.nil? && action != 'note'
      changes = calculate_changes
    end
    changes ||= {}

    CardAuditLog.create!(
      card_id: self.id,
      user_id: user.id,
      action: action,
      changes_json: changes.to_json,
      comment: comment
    )
  end

  # Calculate what fields changed (call before save)
  def calculate_changes
    tracked_fields = %w[card_number card_permissions user_id]

    changes_to_record = {}
    tracked_fields.each do |field|
      if send("#{field}_changed?")
        changes_to_record[field] = {
          old: send("#{field}_was"),
          new: send(field)
        }
      end
    end
    changes_to_record
  end

  # Check if any tracked fields changed
  def tracked_changes?
    %w[card_number card_permissions user_id].any? { |f| send("#{field}_changed?") }
  end
end
```

### Callback Approach (Alternative)

Instead of handling audit logging in the controller, you could use model callbacks:

```ruby
# In Card model - callback approach (alternative)

class Card < ActiveRecord::Base
  # ... existing code ...

  # Store the current user for audit logging (set by controller)
  attr_accessor :modified_by_user, :audit_comment

  after_create :log_creation
  before_update :capture_changes
  after_update :log_update

  private

  def log_creation
    return unless modified_by_user && audit_comment.present?

    create_audit_log(
      user: modified_by_user,
      action: 'create',
      comment: audit_comment,
      changes: {
        card_number: { old: nil, new: card_number },
        card_permissions: { old: nil, new: card_permissions },
        user_id: { old: nil, new: user_id }
      }
    )
  end

  def capture_changes
    @tracked_changes = calculate_changes
  end

  def log_update
    return unless modified_by_user && audit_comment.present?
    return if @tracked_changes.empty? && action != 'note'

    create_audit_log(
      user: modified_by_user,
      action: @tracked_changes.empty? ? 'note' : 'update',
      comment: audit_comment,
      changes: @tracked_changes
    )
  end
end
```

**Recommendation:** The controller approach (shown in next section) is generally cleaner for Rails 3 because:
- More explicit control over when audit logs are created
- Easier to handle the "note-only" scenario
- Avoids complexity with `attr_accessor` for user context

---

## Controller Changes

### Modified: `CardsController`

```ruby
# app/controllers/cards_controller.rb

class CardsController < ApplicationController
  load_and_authorize_resource

  # GET /cards
  def index
    @cards = Card.includes(:user, :card_audit_logs).all
    # Note: May need to optimize query for latest_note
  end

  # GET /cards/:id
  def show
    @card = Card.find(params[:id])
    @audit_logs = @card.card_audit_logs  # Already ordered DESC
  end

  # GET /cards/new
  def new
    @card = Card.new
    # Note: No card ID field shown on new form
  end

  # POST /cards
  def create
    @card = Card.new(card_params)

    # Validate audit comment is present
    if params[:audit_comment].blank?
      @card.errors.add(:base, "Please provide a comment explaining why this card is being created")
      render :new and return
    end

    if @card.save
      # Create audit log entry for creation
      @card.create_audit_log(
        user: current_user,
        action: 'create',
        comment: params[:audit_comment],
        changes: {
          card_number: { old: nil, new: @card.card_number },
          card_permissions: { old: nil, new: @card.card_permissions },
          user_id: { old: nil, new: @card.user_id }
        }
      )

      redirect_to @card, notice: 'Card was successfully created.'
    else
      render :new
    end
  end

  # GET /cards/:id/edit
  def edit
    @card = Card.find(params[:id])
    # Card ID shown as read-only
    # Audit comment field shown (blank, ready for input)
  end

  # PUT /cards/:id
  def update
    @card = Card.find(params[:id])

    # Validate audit comment is present
    if params[:audit_comment].blank?
      @card.errors.add(:base, "Please provide a comment explaining this change")
      render :edit and return
    end

    # Capture changes BEFORE updating
    @card.assign_attributes(card_params)
    tracked_changes = @card.calculate_changes

    # Determine action type
    action_type = tracked_changes.empty? ? 'note' : 'update'

    if @card.save
      # Create audit log entry
      @card.create_audit_log(
        user: current_user,
        action: action_type,
        comment: params[:audit_comment],
        changes: tracked_changes
      )

      redirect_to @card, notice: 'Card was successfully updated.'
    else
      render :edit
    end
  end

  # DELETE /cards/:id
  def destroy
    @card = Card.find(params[:id])

    # Validate audit comment for deletion
    if params[:audit_comment].blank?
      redirect_to cards_path, alert: 'Please provide a reason for deleting this card.'
      return
    end

    # Use soft delete
    @card.soft_delete(current_user, params[:audit_comment])

    redirect_to cards_path, notice: 'Card was successfully deleted.'
  end

  # GET /cards/:id/audit_log (for AJAX modal)
  def audit_log
    @card = Card.find(params[:id])
    @audit_logs = @card.card_audit_logs.includes(:user)

    respond_to do |format|
      format.html { render partial: 'audit_log_modal', layout: false }
      format.json { render json: @audit_logs }
    end
  end

  # POST /cards/:id/add_note (optional: dedicated endpoint for note-only)
  def add_note
    @card = Card.find(params[:id])

    if params[:audit_comment].blank?
      redirect_to @card, alert: 'Note cannot be blank.'
      return
    end

    @card.create_audit_log(
      user: current_user,
      action: 'note',
      comment: params[:audit_comment],
      changes: {}
    )

    redirect_to @card, notice: 'Note was successfully added.'
  end

  private

  # Rails 3 style - params are filtered by attr_accessible in model
  # But we explicitly exclude :id here for safety
  def card_params
    params[:card].except(:id)  # Ensure ID cannot be mass-assigned
  end
end
```

### New Routes

```ruby
# config/routes.rb

resources :cards do
  member do
    get :audit_log      # For AJAX modal: GET /cards/:id/audit_log
    post :add_note      # Optional: POST /cards/:id/add_note
  end
end
```

---

## View Changes

### Modified: `app/views/cards/index.html.erb`

```erb
<h1>Cards</h1>

<table class="table table-striped">
  <thead>
    <tr>
      <th>User</th>
      <th>Note</th>
      <th>DB ID</th>
      <th>Card #</th>
      <th>Access?</th>
      <th>Days Accessed Last Month</th>
      <th>Audit Log</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <% @cards.each do |card| %>
      <tr>
        <td><%= card.user&.name || '(unassigned)' %></td>
        <td><%= truncate(card.latest_note, length: 50) %></td>
        <td><%= card.id %></td>
        <td><%= card.card_number %></td>
        <td><%= card.card_permissions == 1 ? 'Yes' : 'No' %></td>
        <td><%= card.days_accessed_last_month %></td>
        <td>
          <%= link_to 'View', audit_log_card_path(card),
              class: 'btn btn-sm btn-info',
              data: { toggle: 'modal', target: '#auditLogModal' },
              remote: true %>
        </td>
        <td>
          <%= link_to 'Edit', edit_card_path(card), class: 'btn btn-sm btn-default' %>
          <%= link_to 'Delete', card_path(card), method: :delete,
              data: { confirm: 'Are you sure? Please provide a reason.' },
              class: 'btn btn-sm btn-danger' %>
        </td>
      </tr>
    <% end %>
  </tbody>
</table>

<%= link_to 'New Card', new_card_path, class: 'btn btn-primary' %>

<!-- Audit Log Modal -->
<div id="auditLogModal" class="modal fade" tabindex="-1" role="dialog">
  <div class="modal-dialog modal-lg" role="document">
    <div class="modal-content">
      <!-- Content loaded via AJAX -->
    </div>
  </div>
</div>
```

### New Partial: `app/views/cards/_audit_log_modal.html.erb`

```erb
<div class="modal-header">
  <button type="button" class="close" data-dismiss="modal" aria-label="Close">
    <span aria-hidden="true">&times;</span>
  </button>
  <h4 class="modal-title">Audit Log for Card <%= @card.id %></h4>
</div>
<div class="modal-body">
  <p><strong>Card #:</strong> <%= @card.card_number %></p>
  <p><strong>Assigned to:</strong> <%= @card.user&.name || '(unassigned)' %></p>

  <hr>

  <% if @audit_logs.empty? %>
    <p class="text-muted">No audit history available.</p>
  <% else %>
    <table class="table table-condensed table-hover">
      <thead>
        <tr>
          <th>Date</th>
          <th>User</th>
          <th>Action</th>
          <th>Changes</th>
          <th>Notes</th>
        </tr>
      </thead>
      <tbody>
        <% @audit_logs.each do |log| %>
          <tr>
            <td><%= log.created_at.strftime('%Y-%m-%d %H:%M') %></td>
            <td><%= log.user&.name || 'System' %></td>
            <td>
              <span class="label label-<%= audit_action_class(log.action) %>">
                <%= log.action_label %>
              </span>
            </td>
            <td>
              <% if log.note_only? %>
                <em class="text-muted">No changes</em>
              <% else %>
                <ul class="list-unstyled" style="margin-bottom: 0;">
                  <% log.formatted_changes.each do |change| %>
                    <li><small><%= change %></small></li>
                  <% end %>
                </ul>
              <% end %>
            </td>
            <td><%= log.comment %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>
</div>
<div class="modal-footer">
  <button type="button" class="btn btn-default" data-dismiss="modal">Close</button>
</div>
```

### New Helper: `app/helpers/cards_helper.rb`

```ruby
module CardsHelper
  def audit_action_class(action)
    case action
    when 'create' then 'success'
    when 'update' then 'info'
    when 'delete' then 'danger'
    when 'note'   then 'default'
    else 'default'
    end
  end
end
```

### Modified: `app/views/cards/_form.html.erb`

```erb
<%= form_for(@card) do |f| %>
  <% if @card.errors.any? %>
    <div class="alert alert-danger">
      <h4><%= pluralize(@card.errors.count, "error") %> prohibited this card from being saved:</h4>
      <ul>
        <% @card.errors.full_messages.each do |msg| %>
          <li><%= msg %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div class="form-group">
    <%= f.label :user_id, "User" %>
    <%= f.collection_select :user_id, User.order(:name), :id, :name,
        { prompt: "Select a user" },
        { class: 'form-control' } %>
  </div>

  <% if @card.persisted? %>
    <!-- Show DB ID as read-only when editing -->
    <div class="form-group">
      <label>Card DB ID</label>
      <p class="form-control-static"><%= @card.id %></p>
      <p class="help-block">Database ID cannot be changed.</p>
    </div>
  <% end %>

  <div class="form-group">
    <%= f.label :card_number, "Card Number" %>
    <%= f.text_field :card_number, class: 'form-control' %>
  </div>

  <div class="form-group">
    <%= f.label :card_permissions, "Card Permissions" %>
    <%= f.select :card_permissions,
        [['Enabled (Full Access)', 1], ['Disabled (No Access)', 255]],
        {},
        { class: 'form-control' } %>
  </div>

  <hr>

  <!-- Audit Comment (required) -->
  <div class="form-group">
    <%= label_tag :audit_comment, "Change Comment *" %>
    <%= text_area_tag :audit_comment, '',
        class: 'form-control',
        rows: 3,
        required: true,
        placeholder: @card.new_record? ?
          "Why is this card being created? (e.g., 'New member approved for access')" :
          "Why are you making this change? (e.g., 'Card deactivated per member request')" %>
    <p class="help-block">
      <strong>Required:</strong> This comment will be permanently recorded in the audit log.
    </p>
  </div>

  <div class="form-group">
    <%= f.submit @card.new_record? ? 'Create Card' : 'Update Card',
        class: 'btn btn-primary' %>
    <%= link_to 'Cancel', cards_path, class: 'btn btn-default' %>
  </div>
<% end %>
```

### JavaScript for Modal (AJAX)

```javascript
// app/assets/javascripts/cards.js.coffee

$ ->
  # Handle audit log modal loading
  $(document).on 'ajax:success', 'a[data-target="#auditLogModal"]', (e, data) ->
    $('#auditLogModal .modal-content').html(data)
    $('#auditLogModal').modal('show')

  $(document).on 'ajax:error', 'a[data-target="#auditLogModal"]', (e, xhr) ->
    alert('Failed to load audit log. Please try again.')
```

### Modified: Delete Confirmation with Comment

For deletion, we need a way to capture the comment. Options:

**Option A: JavaScript prompt (simple)**
```javascript
// In cards.js.coffee
$(document).on 'click', 'a.delete-card', (e) ->
  e.preventDefault()
  comment = prompt('Please provide a reason for deleting this card:')
  if comment? && comment.trim() != ''
    form = $('<form method="POST">')
      .attr('action', $(this).attr('href'))
      .append($('<input type="hidden" name="_method" value="delete">'))
      .append($('<input type="hidden" name="authenticity_token">').val($('meta[name="csrf-token"]').attr('content')))
      .append($('<input type="hidden" name="audit_comment">').val(comment))
    $('body').append(form)
    form.submit()
  else if comment != null  # User clicked OK but left blank
    alert('A reason is required to delete a card.')
```

**Option B: Custom modal (better UX)**
Create a confirmation modal with a textarea for the deletion reason.

---

## Authorization Changes

### Modified: `app/models/ability.rb`

```ruby
class Ability
  include CanCan::Ability

  def initialize(user)
    # ... existing code ...

    if !user.nil?
      # ... existing user permissions ...

      # Add permission to read own card audit logs
      can :read, CardAuditLog, card: { user_id: user.id }

      if user.admin?
        can :manage, :all
        # Explicit audit log permissions (redundant with :all, but clear)
        can :manage, CardAuditLog
      end

      # Audit logs are NEVER editable or deletable (except by manage :all)
      # Add explicit restrictions if you want even admins blocked:
      # cannot :update, CardAuditLog
      # cannot :destroy, CardAuditLog
    end
  end
end
```

**Note:** If you want audit logs to be truly immutable even for admins:

```ruby
# At the end of ability.rb, after all permissions
cannot :update, CardAuditLog
cannot :destroy, CardAuditLog
```

---

## Migration Strategy

### Execution Order

1. **Create `card_audit_logs` table**
   ```bash
   rails generate migration CreateCardAuditLogs
   # Edit migration file as specified above
   ```

2. **Add soft delete to `cards` table**
   ```bash
   rails generate migration AddSoftDeleteToCards
   # Edit migration file as specified above
   ```

3. **Migrate existing `name` data to audit logs**
   ```bash
   rails generate migration MigrateCardNamesToAuditLogs
   # Edit migration file as specified above
   ```

4. **Run migrations**
   ```bash
   rake db:migrate
   ```

5. **Deploy code changes**
   - Model files
   - Controller changes
   - View changes
   - Routes update

6. **Verify migration**
   - Check that all existing cards have an initial audit log entry
   - Verify `name` data was preserved in audit comments

### Rollback Considerations

- The data migration is **irreversible** by design (audit logs should not be deleted)
- If rollback is needed, the `name` field still exists and can be used temporarily
- Consider keeping `name` field for one release cycle before removing

---

## Testing Considerations

### Unit Tests (Models)

```ruby
# test/unit/card_audit_log_test.rb

require 'test_helper'

class CardAuditLogTest < ActiveSupport::TestCase
  test "requires card_id" do
    log = CardAuditLog.new(user_id: 1, action: 'create', comment: 'test')
    assert_not log.valid?
    assert_includes log.errors[:card_id], "can't be blank"
  end

  test "requires comment" do
    log = CardAuditLog.new(card_id: 1, user_id: 1, action: 'create')
    assert_not log.valid?
    assert_includes log.errors[:comment], "is required - please explain this change"
  end

  test "action must be valid" do
    log = CardAuditLog.new(card_id: 1, user_id: 1, comment: 'test', action: 'invalid')
    assert_not log.valid?
    assert_includes log.errors[:action], "must be create, update, delete, or note"
  end

  test "changes_hash parses JSON correctly" do
    log = CardAuditLog.new(changes_json: '{"card_permissions": {"old": 1, "new": 255}}')
    assert_equal({ "card_permissions" => { "old" => 1, "new" => 255 } }, log.changes_hash)
  end

  test "changes_hash returns empty hash for nil" do
    log = CardAuditLog.new(changes_json: nil)
    assert_equal({}, log.changes_hash)
  end
end
```

### Functional Tests (Controllers)

```ruby
# test/functional/cards_controller_test.rb

require 'test_helper'

class CardsControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "create requires audit_comment" do
    post :create, card: { card_number: '123', user_id: 1, card_permissions: 1 }
    assert_response :success  # Re-renders form
    assert_includes assigns(:card).errors[:base],
      "Please provide a comment explaining why this card is being created"
  end

  test "create with comment creates audit log" do
    assert_difference 'CardAuditLog.count', 1 do
      post :create,
        card: { card_number: '123', user_id: 1, card_permissions: 1 },
        audit_comment: 'New member approved'
    end

    log = CardAuditLog.last
    assert_equal 'create', log.action
    assert_equal 'New member approved', log.comment
    assert_equal @admin.id, log.user_id
  end

  test "update with no changes creates note action" do
    card = cards(:existing)

    put :update,
      id: card.id,
      card: { card_number: card.card_number, card_permissions: card.card_permissions },
      audit_comment: 'Verified during audit'

    log = card.card_audit_logs.first
    assert_equal 'note', log.action
    assert_equal 'Verified during audit', log.comment
  end

  test "update with changes creates update action" do
    card = cards(:existing)

    put :update,
      id: card.id,
      card: { card_number: card.card_number, card_permissions: 255 },
      audit_comment: 'Deactivated per request'

    log = card.card_audit_logs.first
    assert_equal 'update', log.action
    assert_includes log.changes_json, 'card_permissions'
  end

  test "destroy soft deletes and creates audit log" do
    card = cards(:existing)

    delete :destroy, id: card.id, audit_comment: 'Card lost, not needed'

    card.reload
    assert card.deleted?

    log = card.card_audit_logs.first
    assert_equal 'delete', log.action
  end
end
```

---

## Open Questions

### Resolved

| Question | Decision |
|----------|----------|
| Notes immutability | Truly immutable - enforced at model level |
| Existing data migration | Create initial audit entries with `[Migrated]` prefix |
| Card list note display | Most recent audit log comment |
| Change comment requirement | Mandatory |
| Action type selection | Auto-detected (create/update/delete/note) |
| Field tracking | Specific fields with old/new values |
| DB ID editability | Read-only (shown on edit, hidden on new) |
| Soft vs hard delete | Soft delete with preserved audit trail |
| Audit log permissions | Admin only |
| Note-only support | Yes, supported |

### Remaining Questions (for future consideration)

1. **Bulk operations**: If bulk card upload/update is ever needed, how should audit logging work?

2. **API access**: Should the card authorization API (`/cards/authorize/:id`) log accesses, or is that separate from this audit system?

3. **Retention policy**: Should there be a retention policy for old audit logs, or keep forever?

4. **Export functionality**: Should admins be able to export audit logs (CSV/PDF)?

5. **Notifications**: Should certain actions (e.g., card deletion, deactivation) trigger email notifications?

---

## Summary of Files to Create/Modify

### New Files
| File | Purpose |
|------|---------|
| `db/migrate/XXX_create_card_audit_logs.rb` | Create audit log table |
| `db/migrate/XXX_add_soft_delete_to_cards.rb` | Add deleted_at to cards |
| `db/migrate/XXX_migrate_card_names_to_audit_logs.rb` | Data migration |
| `app/models/card_audit_log.rb` | New model |
| `app/views/cards/_audit_log_modal.html.erb` | Modal partial |
| `app/helpers/cards_helper.rb` | Helper for action styling |

### Modified Files
| File | Changes |
|------|---------|
| `app/models/card.rb` | Add associations, soft delete, audit methods |
| `app/models/ability.rb` | Add CardAuditLog permissions |
| `app/controllers/cards_controller.rb` | Add audit logging to CRUD actions |
| `app/views/cards/index.html.erb` | Add Note column, Audit Log link, modal |
| `app/views/cards/_form.html.erb` | Add audit comment field, make ID read-only |
| `app/assets/javascripts/cards.js.coffee` | Modal AJAX handling |
| `config/routes.rb` | Add audit_log and add_note routes |

---

**Document Version:** 1.0
**Next Steps:** Review and approve, then proceed with implementation
