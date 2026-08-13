# Migration guide: Amber::Validators to controller schemas
#
# Amber V2 keeps `Amber::Validators::Params` operational for upgrade
# compatibility. Its `validation` entrypoint is deprecated, with removal
# planned no earlier than a later V2 minor such as 2.5. The exact removal
# release will be announced separately.
#
# A controller schema is enforced automatically before its action:
#
# ```
# # src/schemas/create_user_schema.cr
# class CreateUserSchema < Amber::Schema::Definition
#   content_type "application/json"
#   additional_properties false
#
#   field :email, String, required: true, format: "email"
#   field :password, String, required: true, min_length: 8
# end
#
# # src/controllers/users_controller.cr
# require "../schemas/create_user_schema"
#
# class UsersController < ApplicationController
#   schema :create, CreateUserSchema
#
#   def create
#     input = validated_as(CreateUserSchema)
#     user = User.create!(
#       email: input.email.not_nil!,
#       password: input.password.not_nil!
#     )
#     redirect_to "/users/#{user.id}"
#   end
# end
# ```
#
# Existing actions without `schema` keep their existing params behavior. After
# a schema succeeds, `params` prioritizes normalized schema values and falls
# back to raw params for undeclared keys. Applications can therefore upgrade
# Amber first and migrate one action at a time.
#
# `validate_schema` and `auto_validate` remain source-compatible no-ops for
# early V2 previews. A declared schema is always enforced; annotation-based
# examples from preview documentation are not the authoritative V2 API.
#
# See `docs/guides/schema-api.md` for exact application file locations, error
# statuses, source mapping, CBOR/COSE configuration, response contracts, and
# OpenAPI generation.
