## 2026-06-13 - Added missing labels to scaffolded form templates
**Learning:** In Amber framework templates, using string literal interpolation for labels in ECR (like `<%= label(":#{field.name}") %>`) instead of evaluating the field name (like `<%= label(<%=":#{field.name}"%>) %>`) causes a runtime compilation error 'undefined local variable or method "field"' because the string literal passes the literal ruby interpolation into the generated file rather than interpreting it during scaffolding.
**Action:** Always ensure that when generating variables in scaffold templates, the values are correctly interpolated inside `<%=` tags so that they are evaluated by the generator, not output literally into the resulting file.

## 2026-06-14 - Scaffolding Needs Accessibility
**Learning:** The scaffold templates (ECR and Slang) that generate auth views (registration, sign in, and profile edit) lack proper `<label>` elements for their inputs, which degrades accessibility since screen readers rely on labels rather than placeholder text to give context.
**Action:** Always ensure that generated templates and form scaffolding contain explicit labels associated via the `for`/`id` pattern for maximum accessibility out-of-the-box.

## 2026-06-15 - Improve Auth Scaffold Accessibility
**Learning:** Adding accessibility attributes (aria-label, required) directly to template generators (like auth forms in Amber) creates a multiplicative accessibility benefit, as every new app generated will have accessible auth forms by default.
**Action:** Always look for opportunities to bake accessibility into generators, scaffolds, and UI component libraries so downstream consumers get accessible defaults.
