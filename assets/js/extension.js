let use_vector = false;

import L from "leaflet";
import "mapbox-gl";
import "mapbox-gl-leaflet";
import "leaflet.locatecontrol";
import "./leaflet-marker";
import "./leaflet-icon";

let GeolocateHooks = {};

GeolocateHooks.MapLeaflet = {
	mounted() {
		const view = this;

		console.log("mounting leaflet map");

		if (window.Gon !== undefined) {
			// note: requires phoenix_gon to be set up to load config into the view
			let mapbox_token = window.Gon.getAsset("mapbox_api_key");
			// let protomaps_token = window.Gon.getAsset("protomaps_api_key"); // TODO: integrate https://app.protomaps.com

			if (mapbox_token && mapbox_token != "") {
				const template = document.createElement("template");
				// Warning: remember to update the stylesheet version at the same time as the JS
				template.innerHTML = `
        <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.1/dist/leaflet.css" crossorigin=""/>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/leaflet.locatecontrol@0.76.1/dist/L.Control.Locate.min.css" />
        <div style="width: 100%; height: 100%; min-height: 250px;">
            <slot />
        </div>`;

				const maybe_map_moved = function (e) {
					var bounds = createPolygonFromBounds(e.target, e.target.getBounds());
					console.log(bounds);
					view.pushEvent("map_bounds", bounds._latlngs);
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

				const onLocationFound = function (e) {
					console.log(
						"You are within " +
							e.accuracy +
							" meters from this point" +
							e.latlng,
					);

					view.pushEvent("current_location", {
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
							if (arr.length > 0 && typeof arr[0] === 'number') {
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
							if (fitBounds) {
								this.map = L.map(this.mapElement).fitBounds(fitBounds);
							} else {
								console.log("[LeafletMap] No geometry found, falling back to current location");
								this.map = L.map(this.mapElement).locate({ setView: true });
							}

							// adds https://github.com/domoritz/leaflet-locatecontrol
							L.control
								.locate({ setView: "untilPan", flyTo: true })
								.addTo(this.map);

							this.map.on("locationfound", onLocationFound);
							this.map.options.minZoom = 2;
							if (!use_vector) {
								L.tileLayer(
									"https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
									{
										attribution:
											'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
										maxZoom: 18,
										id: "mapbox/streets-v11",
										tileSize: 512,
										zoomOffset: -1,
										accessToken: window.Gon.getAsset("mapbox_api_key"),
										crossOrigin: "",
									},
								).addTo(this.map);
							} else {
								this.map.options.minZoom = 4;
								L.mapboxGL({
									accessToken: window.Gon.getAsset("mapbox_api_key"),
									style: "mapbox://styles/mapbox/streets-v11",
								}).addTo(this.map);
								this.map.fitWorld();
							}
							this.map.on("moveend", maybe_map_moved);
							this.map.on("zoomend", maybe_map_moved);
							this.defaultIcon = L.icon({
								iconUrl: "https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon.png",
							});

							// Add markers after map is ready
							const markerElements = this.querySelectorAll("leaflet-marker");
							markerElements.forEach((markerEl) => {
								const lat = markerEl.getAttribute("lat");
								const lng = markerEl.getAttribute("lng");
								const marker = L.marker([lat, lng], {
									icon: this.defaultIcon,
								}).addTo(this.map);
								const popup = markerEl.getAttribute("popup");
								if (popup) {
									marker.bindPopup(popup);
									marker.on("click", function (e) {
										this.openPopup();
									});
								}
							});
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

				if (window.customElements.get("leaflet-map")) {
					console.log("leaftlet already defined");
				} else {
					window.customElements.define("leaflet-map", LeafletMap);
				}

			} else {
				console.log(
					"ERROR: Skipping map initialisation because no mapbox_api_key is available"
				);
			}
		} else {
			console.log(
				"ERROR: Skipping map initialisation because window.Gon is not available on the page and so can't read mapbox_api_key from it"
			);
		}
	},
};

export { GeolocateHooks };
