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
        <div style="width: 100%; height: 100%; min-height: 600px;">
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

						var points = this.getAttribute("points");
						var lines = this.getAttribute("lines");
						var polygons = this.getAttribute("polygons");
						var multiPolygons = this.getAttribute("multi-polygons");
						
						console.log("Points:", points);
						console.log("Lines:", lines);
						console.log("Polygons:", polygons);
						console.log("MultiPolygons:", multiPolygons);

						// First create the map
						this.map = L.map(this.mapElement);

						// We'll collect all bounds to calculate the overall view later
						let allBoundsPoints = [];

						// adds https://github.com/domoritz/leaflet-locatecontrol
						L.control
							.locate({ setView: "untilPan", flyTo: true })
							.addTo(this.map);

						this.map.on("locationfound", onLocationFound);

						// this.map = L.map(this.mapElement).setView(
						//   [this.getAttribute("lat"), this.getAttribute("lng")],
						//   13
						// );
						console.log(use_vector);
						this.map.options.minZoom = 2;
						if (!use_vector) {
							console.log("map: use tiles");

							L.tileLayer(
								"https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}",
								{
									attribution:
										'Map data &copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a> contributors, <a href="https://creativecommons.org/licenses/by-sa/2.0/">CC-BY-SA</a>, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
									maxZoom: 18,
									id: "mapbox/streets-v11",
									tileSize: 512,
									zoomOffset: -1,
									accessToken: mapbox_token,
									crossOrigin: "",
								},
							).addTo(this.map);
						} else {
							console.log("map: use vectors from openmaptiles.org");

							this.map.options.minZoom = 4;

							// L.tileLayer('https://api.mapbox.com/styles/v1/{id}/tiles/{z}/{x}/{y}?access_token={accessToken}', {
							//     attribution: 'Map data &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, Imagery © <a href="https://www.mapbox.com/">Mapbox</a>',
							//     maxZoom: 18,
							//     id: 'mapbox/streets-v11',
							//     tileSize: 512,
							//     zoomOffset: -1,
							//     accessToken: 'your.mapbox.access.token'
							// }).addTo(mymap);

							L.mapboxGL({
								accessToken: mapbox_token,
								style: "mapbox://styles/mapbox/streets-v11", // style URL
								// style: 'https://openmaptiles.github.io/maptiler-toner-gl-style/style-cdn.json'
								// style: 'https://openmaptiles.github.io/maptiler-terrain-gl-style/style-cdn.json'
								// style: 'https://maputnik.github.io/osm-liberty/style.json'
								// style: 'https://openmaptiles.github.io/maptiler-basic-gl-style/style-cdn.json'
								// style: 'https://openmaptiles.github.io/osm-bright-gl-style/style-cdn.json'
								// style: 'https://openmaptiles.github.io/maptiler-3d-gl-style/style-cdn.json'
							}).addTo(this.map);

							this.map.fitWorld();
						}

						this.map.on("moveend", maybe_map_moved);
						this.map.on("zoomend", maybe_map_moved);

						this.defaultIcon = L.icon({
							iconUrl:
								"https://unpkg.com/leaflet@1.7.1/dist/images/marker-icon.png",
							// iconSize: [32, 32],
						});
					}

					connectedCallback() {
						// Add markers (points)
						this.addMarkers();
						
						// Add lines
						this.addLines();
						
						// Add polygons
						this.addPolygons();
						
						// Add multi-polygons
						this.addMultiPolygons();
						
						// Fit map to all elements if we have any
						this.fitMapToElements();
					}
					
					addMarkers() {
						const markerElements = this.querySelectorAll("leaflet-marker");
						const points = [];
						
						markerElements.forEach((markerEl) => {
							const lat = parseFloat(markerEl.getAttribute("lat"));
							const lng = parseFloat(markerEl.getAttribute("lng"));
							
							if (lat && lng && !isNaN(lat) && !isNaN(lng)) {
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

								const iconEl = markerEl.querySelector("leaflet-icon");
								if (iconEl) {
									const iconSize = [
										iconEl.getAttribute("width"),
										iconEl.getAttribute("height"),
									];
									
									const iconUrl = iconEl.getAttribute("icon-url");
									if (iconUrl) {
										marker.setIcon(
											L.icon({
												iconUrl: iconUrl,
												iconSize: iconSize,
												iconAnchor: iconSize,
											})
										);
									}
								}
								
								// Add point to our bounds calculation
								points.push([lat, lng]);
							}
						});
						
						return points;
						}
					
					addLines() {
						const lines = this.getAttribute("lines");
						if (!lines || lines === "[]") return [];
						
						try {
							const parsedLines = JSON.parse(lines.replace(/&quot;/g, '"').replace(/&#39;/g, "'"));
							const lineElements = this.querySelectorAll("leaflet-polyline");
							const bounds = [];
							
							lineElements.forEach((lineElement, index) => {
								if (index >= parsedLines.length) return;
								
								const lineData = parsedLines[index];
								if (!lineData || !Array.isArray(lineData) || lineData.length < 2) return;
								
								const color = lineElement.getAttribute("color") || "blue";
								const weight = parseInt(lineElement.getAttribute("weight") || "3");
								const popup = lineElement.getAttribute("popup");
								
								const polyline = L.polyline(lineData, { color, weight });
								if (popup) {
									polyline.bindPopup(popup);
								}
								
								polyline.addTo(this.map);
								bounds.push(...lineData);
							});
							
							return bounds;
						} catch (e) {
							console.error("Error parsing lines data:", e);
							return [];
						}
					}
					
					addPolygons() {
						const polygons = this.getAttribute("polygons");
						if (!polygons || polygons === "[]") return [];
						
						try {
							const parsedPolygons = JSON.parse(polygons.replace(/&quot;/g, '"').replace(/&#39;/g, "'"));
							const polygonElements = this.querySelectorAll("leaflet-polygon");
							const bounds = [];
							
							polygonElements.forEach((polygonElement, index) => {
								if (index >= parsedPolygons.length) return;
								
								const polygonData = parsedPolygons[index];
								if (!polygonData || !Array.isArray(polygonData) || polygonData.length < 1) return;
								
								const outerRing = polygonData[0];
								const holes = polygonData.slice(1);
								
								const color = polygonElement.getAttribute("color") || "green";
								const fillColor = polygonElement.getAttribute("fill-color") || color;
								const fillOpacity = parseFloat(polygonElement.getAttribute("fill-opacity") || "0.2");
								const popup = polygonElement.getAttribute("popup");
								
								const polygon = L.polygon([outerRing, ...holes], { 
									color, 
									fillColor, 
									fillOpacity 
								});
								
								if (popup) {
									polygon.bindPopup(popup);
								}
								
								polygon.addTo(this.map);
								bounds.push(...outerRing);
							});
							
							return bounds;
						} catch (e) {
							console.error("Error parsing polygon data:", e);
							return [];
						}
					}
					
					addMultiPolygons() {
						const multiPolygons = this.getAttribute("multi-polygons");
						if (!multiPolygons || multiPolygons === "[]") return [];
						
						try {
							const parsedMultiPolygons = JSON.parse(multiPolygons.replace(/&quot;/g, '"').replace(/&#39;/g, "'"));
							const multiPolygonElements = this.querySelectorAll("leaflet-multi-polygon");
							const bounds = [];
							
							multiPolygonElements.forEach((multiPolygonElement, index) => {
								if (index >= parsedMultiPolygons.length) return;
								
								const multiPolygonData = parsedMultiPolygons[index];
								if (!multiPolygonData || !Array.isArray(multiPolygonData)) return;
								
								const color = multiPolygonElement.getAttribute("color") || "purple";
								const fillColor = multiPolygonElement.getAttribute("fill-color") || color;
								const fillOpacity = parseFloat(multiPolygonElement.getAttribute("fill-opacity") || "0.2");
								const popup = multiPolygonElement.getAttribute("popup");
								
								// Each item in multiPolygonData is a polygon with outer ring and optional holes
								multiPolygonData.forEach(polygonData => {
									if (!polygonData || !Array.isArray(polygonData) || polygonData.length < 1) return;
									
									const outerRing = polygonData[0];
									const holes = polygonData.slice(1);
									
									const polygon = L.polygon([outerRing, ...holes], { 
										color, 
										fillColor, 
										fillOpacity 
									});
									
									if (popup) {
										polygon.bindPopup(popup);
									}
									
									polygon.addTo(this.map);
									bounds.push(...outerRing);
								});
							});
							
							return bounds;
						} catch (e) {
							console.error("Error parsing multi-polygon data:", e);
							return [];
						}
					}
					
					fitMapToElements() {
						// Start with any points from markers
						let allBounds = this.addMarkers() || [];
						
						// Add lines points
						const linePoints = this.addLines();
						if (linePoints && linePoints.length > 0) {
							allBounds = [...allBounds, ...linePoints];
						}
						
						// Add polygon points
						const polygonPoints = this.addPolygons();
						if (polygonPoints && polygonPoints.length > 0) {
							allBounds = [...allBounds, ...polygonPoints];
						}
						
						// Add multi-polygon points
						const multiPolygonPoints = this.addMultiPolygons();
						if (multiPolygonPoints && multiPolygonPoints.length > 0) {
							allBounds = [...allBounds, ...multiPolygonPoints];
						}
						
						// Also try to parse points from the points attribute
						const pointsAttr = this.getAttribute("points");
						if (pointsAttr && pointsAttr !== "[]") {
							try {
								const parsedPoints = JSON.parse(pointsAttr.replace(/&quot;/g, '"').replace(/&#39;/g, "'"));
								if (Array.isArray(parsedPoints) && parsedPoints.length > 0) {
									allBounds = [...allBounds, ...parsedPoints];
								}
							} catch (e) {
								console.error("Error parsing points attribute:", e);
							}
						}
						
						// If we have points, fit bounds
						if (allBounds.length > 0) {
							try {
								this.map.fitBounds(allBounds);
							} catch (e) {
								console.error("Error fitting bounds:", e);
								// Fallback to default view
								this.map.setView([0, 0], 2);
							}
						} else {
							// No points, use default view
							this.map.setView([0, 0], 2);
						}
					}
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
