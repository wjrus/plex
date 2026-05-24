import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["bar"]
  static values = {
    duration: { type: Number, default: 5000 }
  }

  connect() {
    this.dismissTimeout = window.setTimeout(() => this.dismiss(), this.durationValue)

    window.requestAnimationFrame(() => {
      this.barTarget.style.transition = `width ${this.durationValue}ms linear`
      this.barTarget.style.width = "0%"
    })
  }

  disconnect() {
    window.clearTimeout(this.dismissTimeout)
  }

  dismiss() {
    window.clearTimeout(this.dismissTimeout)
    this.element.classList.add("opacity-0", "-translate-y-2")
    window.setTimeout(() => this.element.remove(), 160)
  }
}
