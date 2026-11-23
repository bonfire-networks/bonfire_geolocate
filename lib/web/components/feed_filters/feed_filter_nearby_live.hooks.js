// "Detect location" in the feed filter editor's Nearby row: the browser's position is asked for only when the button is pressed, then sent to the editor, which hands it to this extension's handler to round and save
export default {
  mounted() {
    this.button = this.el.querySelector("[data-role=detect_location]");
    this.error = this.el.querySelector("[data-role=detect_location_error]");
    this.onClick = () => this.detect();
    this.button?.addEventListener("click", this.onClick);

    this.input = this.el.querySelector("input[name=place]");
    this.submit = this.el.querySelector("[data-role=search_place]");
    this.onInput = () => this.toggleSubmit();
    this.input?.addEventListener("input", this.onInput);
    this.syncSaved();
  },

  updated() {
    this.syncSaved();
  },

  destroyed() {
    this.button?.removeEventListener("click", this.onClick);
    this.input?.removeEventListener("input", this.onInput);
  },

  // the value the server rendered is the saved (or last searched) place name
  syncSaved() {
    if (!this.input) return;
    this.saved = this.input.defaultValue;
    this.toggleSubmit();
  },

  toggleSubmit() {
    if (!this.submit || !this.input) return;
    const value = this.input.value.trim();
    this.submit.classList.toggle("hidden", value === "" || value === this.saved.trim());
  },

  detect() {
    this.showError(null);

    if (!navigator.geolocation) {
      this.showError(this.el.dataset.unsupported);
      return;
    }

    navigator.geolocation.getCurrentPosition(
      (position) =>
        this.pushEventTo(this.el, "Bonfire.Geolocate:set_location", {
          lat: position.coords.latitude,
          long: position.coords.longitude,
        }),
      () => this.showError(this.el.dataset.denied),
      { maximumAge: 60000, timeout: 15000 },
    );
  },

  showError(message) {
    if (!this.error) return;
    this.error.textContent = message || "";
    this.error.hidden = !message;
  },
};
