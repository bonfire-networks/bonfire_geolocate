// The map's hook, in the main bundle: it loads the map itself (map.js, built on its own by `build.ext` as `/assets/geolocate_map.js`, with Leaflet and MapLibre) only on pages with a map, as Milkdown's editor does.

let GeolocateHooks = {};

let mapModule;
function loadMapModule(url) {
	return (mapModule ||= import(url));
}

// the hook of the map an element is in: the `leaflet-map` element is defined once, by the first map's hook, so its handlers find the current map's hook from the element rather than keeping the first one (gone after navigating)
const mapHookOf = (el) =>
	el && el.closest ? el.closest("[phx-hook=MapLeaflet]")?.__bonfireMapHook : null;

GeolocateHooks.MapLeaflet = {
	mounted() {
		this.el.__bonfireMapHook = this;

		console.log("mounting leaflet map");

		// a map style (`style-url`, the `openfreemap` backend), or Mapbox's key (in Gon, the `mapbox` backend)
		const mapbox_key = window.Gon?.getAsset("mapbox_api_key");
		if (
			this.el.querySelector("leaflet-map[style-url]") ||
			(mapbox_key && mapbox_key != "")
		) {
			const url =
				this.el.dataset.mapBundle ||
				new URL("/assets/geolocate_map.js", window.location.origin).href;

			loadMapModule(url)
				.then((module) => module.defineMapElements(mapHookOf))
				.catch((error) => console.error("[LeafletMap] Could not load the map", error));
		} else {
			console.log(
				"ERROR: Skipping map initialisation because there is neither a map style (style-url) nor a mapbox_api_key",
			);
		}
	},
};

export { GeolocateHooks };
