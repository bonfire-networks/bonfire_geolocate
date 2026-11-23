// The map: Leaflet, with Mapbox's raster tiles or a map style (eg. OpenFreeMap's) drawn by MapLibre, and the `leaflet-*` elements MapLive renders. Built on its own by `build.ext` (as `/assets/geolocate_map.js`), and loaded by the `MapLeaflet` hook (extension.js) only on pages with a map, as it's large.
// (moved from extension.js, which was in the main bundle on every page)

import L from "leaflet";
// vector maps (a map style, eg. OpenFreeMap's) drawn by MapLibre inside the Leaflet map
import { addProtocol, setWorkerUrl } from "maplibre-gl";
import { maplibreGL } from "@maplibre/maplibre-gl-leaflet";
import { Protocol as PMTilesProtocol } from "pmtiles";
// the ES module (since 0.82), which doesn't add `L.control.locate`
import { LocateControl } from "leaflet.locatecontrol";
import "./leaflet-marker";
import "./leaflet-icon";

// MapLibre's worker, from this instance (copied by `build.ext`), rather than from a `blob:` URL
setWorkerUrl("/assets/maplibre-gl-worker.mjs");
// styles can use a self-hosted Protomaps file (`pmtiles://https://...`)
addProtocol("pmtiles", new PMTilesProtocol().tile);

// Defines the map's elements, once; `mapHookOf(el)` gives the hook of the map an element is in (the elements outlive the hook that first loaded them)
export function defineMapElements(mapHookOf) {
	if (window.customElements.get("leaflet-map")) {
		console.log("leaftlet already defined");
		return;
	}

	const template = document.createElement("template");
	// Warning: remember to update the stylesheet version at the same time as the JS
	template.innerHTML = `
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" crossorigin=""/>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/leaflet.locatecontrol@0.91.0/dist/L.Control.Locate.min.css" />
        <link rel="stylesheet" href="https://unpkg.com/maplibre-gl@6.19.0/dist/maplibre-gl.css" crossorigin=""/>
        <style>
          /* a marker with a class (eg. a topic swatch) and/or an icon: a pin in the ink colour the page gives that class (--topic-ink), its icon in the page's own background colour, so it reads on the ink in light and dark. The shape is a square with three round corners, turned so the sharp one is the tip */
          .map-pin { background: none; border: 0; }
          .map-pin-shape { box-sizing: border-box; display: grid; place-items: center; width: 28px; height: 28px; background-color: var(--pin-ink, var(--color-base-content, #555)); border: 2px solid var(--color-base-100, #fff); border-radius: 50% 50% 50% 0; transform: rotate(-45deg); box-shadow: 0 1px 4px rgb(0 0 0 / 0.4); }
          .map-pin-icon { width: 14px; height: 14px; transform: rotate(45deg); background-color: var(--color-base-100, #fff); mask-repeat: no-repeat; mask-position: center; mask-size: contain; -webkit-mask-repeat: no-repeat; -webkit-mask-position: center; -webkit-mask-size: contain; }
        </style>
        <div style="width: 100%; height: 100%; min-height: 250px;">
            <slot />
        </div>`;

	// A marker's pin (a `divIcon`) for the `marker-class` and `marker-icon` the element has; null with neither, which leaves the default marker. The map is in a shadow root, which the page's styles do not reach: so the class's `--topic-ink` and the icon's mask are read from the page (computed on probes in the map's own place in the page, so under its theme) and set on the pin, whose shape is styled in the template above. The names are only ever set as attributes and properties, never as HTML.
	const pinIcon = function (markerEl, host) {
		const cls = markerEl.getAttribute("marker-class");
		const icon = markerEl.getAttribute("marker-icon");
		if (!cls && !icon) return null;

		const probe = function (setup) {
			const el = document.createElement("span");
			el.style.display = "none";
			setup(el);
			host.appendChild(el);
			const style = getComputedStyle(el);
			const found = {
				ink: style.getPropertyValue("--topic-ink").trim(),
				mask: style.maskImage || style.webkitMaskImage,
			};
			el.remove();
			return found;
		};

		const ink = cls ? probe((el) => (el.className = cls)).ink : "";
		const mask = icon ? probe((el) => el.setAttribute("iconify", icon)).mask : "";
		if (!ink && (!mask || mask === "none")) return null;

		const shape = document.createElement("div");
		shape.className = "map-pin-shape";
		if (ink) shape.style.setProperty("--pin-ink", ink);
		if (mask && mask !== "none") {
			const glyph = document.createElement("span");
			glyph.className = "map-pin-icon";
			glyph.style.maskImage = mask;
			glyph.style.webkitMaskImage = mask;
			shape.appendChild(glyph);
		}

		// the tip of the turned square is the point on the map
		return L.divIcon({
			className: "map-pin",
			html: shape,
			iconSize: [28, 28],
			iconAnchor: [14, 34],
			popupAnchor: [0, -34],
		});
	};

	const maybe_map_moved = function (e, el) {
		var bounds = createPolygonFromBounds(e.target, e.target.getBounds());
		console.log(bounds);
		// to the map component (`pushEvent` goes to the page's LiveView, which has no handler for it), as a map of params, which LiveView's handlers take
		const hook = mapHookOf(el);
		if (hook) hook.pushEventTo(hook.el, "map_bounds", { bounds: bounds._latlngs });
	};

	// The map's bounds as a box, for a page that loads its own things for the area in view (`report-bounds`): sent to the map component (which tells its page), as numbers of degrees; west and east may lie past 180 when the map has been panned round the world
	const report_map_moved = function (map, el) {
		const hook = mapHookOf(el);
		if (!hook) return;
		const bounds = map.getBounds();
		hook.pushEventTo(hook.el, "map_moved", {
			south: bounds.getSouth(),
			west: bounds.getWest(),
			north: bounds.getNorth(),
			east: bounds.getEast(),
		});
	};

	/// Takes an L.latLngBounds object and returns an 8 point L.polygon.
	/// L.rectangle takes an L.latLngBounds object in its constructor but this only creates a polygon with 4 points.
	/// This becomes an issue when you try and do spatial queries in SQL because when the 4 point polygon is applied
	/// to the curvature of the earth it loses it's "rectangular-ness".
	/// The 8 point polygon returned from this method will keep it's shape a lot more.
	/// <param name="map">L.map object</param>
	/// <returns type="">L.Polygon with 8 points starting in the bottom left and finishing in the center left</returns>
	const createPolygonFromBounds = function (map, latLngBounds) {
		var center = latLngBounds.getCenter();
		var map_center = map.getCenter();
		var latlngs = [];

		latlngs.push(latLngBounds.getSouthWest()); //bottom left
		latlngs.push({ lat: latLngBounds.getSouth(), lng: center.lng }); //bottom center
		latlngs.push(latLngBounds.getSouthEast()); //bottom right
		latlngs.push({ lat: center.lat, lng: latLngBounds.getEast() }); // center right
		latlngs.push(latLngBounds.getNorthEast()); //top right
		latlngs.push({ lat: latLngBounds.getNorth(), lng: map_center.lng }); //top center
		latlngs.push(latLngBounds.getNorthWest()); //top left
		latlngs.push({ lat: map_center.lat, lng: latLngBounds.getWest() }); //center left

		return new L.polygon(latlngs);
	};

	const onLocationFound = function (e, el) {
		console.log(
			"You are within " + e.accuracy + " meters from this point" + e.latlng,
		);

		// to the map component, as `map_bounds`
		const hook = mapHookOf(el);
		if (hook)
			hook.pushEventTo(hook.el, "current_location", {
				location: e.latlng,
				accuracy: e.accuracy,
			});
	};

	class LeafletMap extends HTMLElement {
		constructor() {
			super();
			this.attachShadow({ mode: "open" });
			this.shadowRoot.appendChild(template.content.cloneNode(true));
			this.mapElement = this.shadowRoot.querySelector("div");
		}

		connectedCallback() {
			// Helper to ensure array of pairs
			function toLatLngPairs(arr) {
				if (arr.length > 0 && typeof arr[0] === "number") {
					let pairs = [];
					for (let i = 0; i < arr.length; i += 2) {
						pairs.push([arr[i], arr[i + 1]]);
					}
					return pairs;
				}
				return arr;
			}
			// Wait for children to be parsed
			setTimeout(() => {
				let points = [];
				try {
					points = JSON.parse(this.getAttribute("points") || "[]");
				} catch (e) {
					console.warn("[LeafletMap] Invalid points JSON", this.getAttribute("points"), e);
				}
				let fitBounds = null;
				if (points.length > 0) {
					points = toLatLngPairs(points);
					console.log("[LeafletMap] Using points for fitBounds", points);
					fitBounds = new L.LatLngBounds(points);
				} else {
					// Try to extract bounds from polylines, polygons, or multi-polygons
					const getAllCoords = (selector, attr) =>
						Array.from(this.querySelectorAll(selector))
							.map((el) => {
								try {
									return JSON.parse(el.getAttribute(attr) || "[]");
								} catch (e) {
									console.warn(`[LeafletMap] Invalid JSON in ${selector} ${attr}`, el.getAttribute(attr), e);
									return [];
								}
							})
							.flat(2);
					let coords = getAllCoords("leaflet-polyline", "points");
					if (coords.length > 0) {
						coords = toLatLngPairs(coords);
						console.log("[LeafletMap] Using polyline for fitBounds", coords);
					}
					if (coords.length === 0) {
						coords = getAllCoords("leaflet-polygon", "points");
						if (coords.length > 0) {
							coords = toLatLngPairs(coords);
							console.log("[LeafletMap] Using polygon for fitBounds", coords);
						}
					}
					if (coords.length === 0) {
						coords = getAllCoords("leaflet-multi-polygon", "polygons");
						if (coords.length > 0) {
							coords = toLatLngPairs(coords);
							console.log("[LeafletMap] Using multi-polygon for fitBounds", coords);
						}
					}
					if (coords.length > 0) {
						fitBounds = new L.LatLngBounds(coords);
					}
				}
				// a view the page gives (`fit-bounds`, `[[south, west], [north, east]]`, eg. the area around the viewer) wins over the one the markers make
				try {
					const given = JSON.parse(this.getAttribute("fit-bounds") || "null");
					if (Array.isArray(given) && given.length === 2) fitBounds = new L.LatLngBounds(given);
				} catch (e) {
					console.warn("[LeafletMap] Invalid fit-bounds JSON", this.getAttribute("fit-bounds"), e);
				}
				if (fitBounds) {
					this.map = L.map(this.mapElement).fitBounds(fitBounds);
				} else {
					console.log("[LeafletMap] No geometry found, falling back to current location");
					// the view found by locating, or the world one, is not the user moving the map
					this.skipNextMove = true;
					// the user's location if allowed, else (refused, or not found) a world view, as a map without a view draws no tiles; not both, so no tiles are loaded twice
					this.map = L.map(this.mapElement);
					this.map.once("locationerror", (e) => {
						console.log("[LeafletMap] No location, showing the world", e.message);
						// zoom 1: MapLibre draws one level lower, so one world tile instead of four
						// this.map.setView([20, 0], 2);
						this.map.setView([20, 0], 1);
					});
					this.map.locate({ setView: true });
				}

				// adds https://github.com/domoritz/leaflet-locatecontrol
				new LocateControl({ setView: "untilPan", flyTo: true }).addTo(this.map);

				// only a map that loads the places in view (`live-bounds`) is told where it is; a map of given places (eg. the events map) sends nothing
				const live_bounds = this.hasAttribute("live-bounds");
				if (live_bounds) this.map.on("locationfound", (e) => onLocationFound(e, this));
				// 1 so the world view (zoom 1) is not clamped
				// this.map.options.minZoom = 2;
				this.map.options.minZoom = 1;

				// the instance's maps backend decides: a map style (`style-url`, the `openfreemap` backend) drawn by MapLibre as vector tiles, else Mapbox's raster tiles (the `mapbox` backend, whose key is in Gon)
				const style_url = this.getAttribute("style-url");
				const mapbox_key = window.Gon?.getAsset("mapbox_api_key");
				if (style_url) {
					// MapLibre adds the style's attribution (eg. OpenFreeMap, OpenStreetMap)
					maplibreGL({ style: style_url }).addTo(this.map);
				} else if (mapbox_key && mapbox_key != "") {
					L.tileLayer(
						"https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
						{
							attribution:
								'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
							maxZoom: 18,
							id: "mapbox/streets-v11",
							tileSize: 512,
							zoomOffset: -1,
							accessToken: mapbox_key,
							crossOrigin: "",
						},
					).addTo(this.map);
				}

				if (live_bounds) {
					this.map.on("moveend", (e) => maybe_map_moved(e, this));
					this.map.on("zoomend", (e) => maybe_map_moved(e, this));
				}
				// a page that loads its own things for the area in view (`report-bounds`) is told where the map is, only after the user has moved it (not for the view it was given), and once it stops moving
				if (this.hasAttribute("report-bounds")) {
					let timer;
					this.map.on("moveend", () => {
						if (this.skipNextMove) {
							this.skipNextMove = false;
							return;
						}
						clearTimeout(timer);
						timer = setTimeout(() => report_map_moved(this.map, this), 400);
					});
				}
				this.defaultIcon = L.icon({
					iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
				});

				// The markers are drawn from the `leaflet-marker` elements, and again whenever they change (a page can replace them as the map moves), with the view left as the user has it. Not redrawn when they are the same, so an open popup stays open
				this.markerLayer = L.layerGroup().addTo(this.map);
				let drawn = null;
				const drawMarkers = () => {
					const markerElements = Array.from(this.querySelectorAll("leaflet-marker"));
					const signature = JSON.stringify(
						markerElements.map((markerEl) =>
							["lat", "lng", "popup", "marker-class", "marker-icon"].map((name) =>
								markerEl.getAttribute(name),
							),
						),
					);
					if (signature === drawn) return;
					drawn = signature;
					this.markerLayer.clearLayers();
					markerElements.forEach((markerEl) => {
						const lat = markerEl.getAttribute("lat");
						const lng = markerEl.getAttribute("lng");
						const marker = L.marker([lat, lng], {
							icon: pinIcon(markerEl, this) || this.defaultIcon,
						}).addTo(this.markerLayer);
						const popup = markerEl.getAttribute("popup");
						if (popup) {
							marker.bindPopup(popup);
							marker.on("click", function (e) {
								this.openPopup();
							});
						}
					});
				};
				// Add markers after map is ready
				drawMarkers();
				let redraw = false;
				new MutationObserver(() => {
					if (redraw) return;
					redraw = true;
					setTimeout(() => {
						redraw = false;
						drawMarkers();
					}, 0);
				}).observe(this, { childList: true, subtree: true, attributes: true });
			}, 0);
		}
	}

	// --- Custom elements for polylines, polygons, and multi-polygons ---

	class LeafletPolyline extends HTMLElement {
		connectedCallback() {
			let points = [];
			try {
				points = JSON.parse(this.getAttribute("points") || "[]");
			} catch (e) {
				console.warn("[LeafletPolyline] Invalid points JSON", this.getAttribute("points"), e);
			}
			const color = this.getAttribute("color") || "blue";
			const weight = parseInt(this.getAttribute("weight") || "3");
			const popup = this.getAttribute("popup") || null;
			const map = this.closest("leaflet-map").map;
			if (points.length > 0 && map) {
				const polyline = L.polyline(points, { color, weight }).addTo(map);
				if (popup) polyline.bindPopup(popup);
			}
		}
	}

	class LeafletPolygon extends HTMLElement {
		connectedCallback() {
			let points = [];
			let holes = [];
			try {
				points = JSON.parse(this.getAttribute("points") || "[]");
			} catch (e) {
				console.warn("[LeafletPolygon] Invalid points JSON", this.getAttribute("points"), e);
			}
			try {
				holes = JSON.parse(this.getAttribute("holes") || "[]");
			} catch (e) {
				console.warn("[LeafletPolygon] Invalid holes JSON", this.getAttribute("holes"), e);
			}
			const color = this.getAttribute("color") || "green";
			const fillColor = this.getAttribute("fill-color") || color;
			const fillOpacity = parseFloat(this.getAttribute("fill-opacity") || "0.4");
			const popup = this.getAttribute("popup") || null;
			const map = this.closest("leaflet-map").map;
			if (points.length > 0 && map) {
				const polygon = L.polygon([points, ...holes], { color, fillColor, fillOpacity }).addTo(map);
				if (popup) polygon.bindPopup(popup);
			}
		}
	}

	class LeafletMultiPolygon extends HTMLElement {
		connectedCallback() {
			let polygons = [];
			try {
				polygons = JSON.parse(this.getAttribute("polygons") || "[]");
			} catch (e) {
				console.warn("[LeafletMultiPolygon] Invalid polygons JSON", this.getAttribute("polygons"), e);
			}
			const color = this.getAttribute("color") || "purple";
			const fillColor = this.getAttribute("fill-color") || color;
			const fillOpacity = parseFloat(this.getAttribute("fill-opacity") || "0.3");
			const popup = this.getAttribute("popup") || null;
			const map = this.closest("leaflet-map").map;
			if (polygons.length > 0 && map) {
				const multiPolygon = L.multiPolygon(polygons, { color, fillColor, fillOpacity }).addTo(map);
				if (popup) multiPolygon.bindPopup(popup);
			}
		}
	}

	if (!window.customElements.get("leaflet-polyline")) {
		window.customElements.define("leaflet-polyline", LeafletPolyline);
	}
	if (!window.customElements.get("leaflet-polygon")) {
		window.customElements.define("leaflet-polygon", LeafletPolygon);
	}
	if (!window.customElements.get("leaflet-multi-polygon")) {
		window.customElements.define("leaflet-multi-polygon", LeafletMultiPolygon);
	}

	window.customElements.define("leaflet-map", LeafletMap);
}
