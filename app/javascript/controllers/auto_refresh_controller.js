import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 10000 },
    url: String,
  }

  connect() {
    this.start()
  }

  disconnect() {
    this.stop()
  }

  start() {
    this.stop()
    this.timer = window.setInterval(() => this.refresh(), this.intervalValue)
  }

  stop() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }

  async refresh() {
    if (!this.urlValue) return

    try {
      const response = await fetch(this.urlWithCacheBust(), {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest",
        },
      })
      if (!response.ok) return

      this.element.innerHTML = await response.text()
    } catch (_error) {
      // Keep the existing content visible until the next polling attempt.
    }
  }

  urlWithCacheBust() {
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("_", Date.now())
    return url.toString()
  }
}
