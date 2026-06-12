// app/javascript/controllers/image_modal_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image"]

  open(event) {
    event.preventDefault()
    event.stopPropagation()

    this.imageTarget.src = event.params.src
    this.imageTarget.alt = event.params.alt || ""
    this.dialogTarget.classList.remove("hidden")
    this.dialogTarget.classList.add("flex")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.dialogTarget.classList.add("hidden")
    this.dialogTarget.classList.remove("flex")
    this.imageTarget.src = ""
    document.body.classList.remove("overflow-hidden")
  }
}
