import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "title", "body", "confirmButton"]

  confirmSubmit(event) {
    const form = event.target
    if (form.dataset.confirmWhenEmpty === "true" && this.hasSelectedOptions(form)) return
    if (form.dataset.confirmed === "true") return

    event.preventDefault()
    this.pendingForm = form
    this.titleTarget.textContent = form.dataset.confirmTitle || "Confirm action"
    this.bodyTarget.textContent = form.dataset.confirmBody || "This action cannot be undone."
    this.confirmButtonTarget.textContent = form.dataset.confirmButton || "Confirm"
    this.dialogTarget.showModal()
  }

  cancel() {
    this.pendingForm = null
    this.dialogTarget.close()
  }

  submit() {
    if (!this.pendingForm) return

    this.pendingForm.dataset.confirmed = "true"
    this.dialogTarget.close()
    this.pendingForm.requestSubmit()
  }

  hasSelectedOptions(form) {
    const selectedOptions = Array.from(form.querySelectorAll("select[multiple] option")).some((option) => option.selected)
    const checkedBoxes = Array.from(form.querySelectorAll("input[type='checkbox'][name='library_ids[]']")).some((checkbox) => checkbox.checked)

    return selectedOptions || checkedBoxes
  }
}
