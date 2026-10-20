// A name as it goes into a file name: "Porada s Šárkou!" -> porada-s-sarkou.
// Accents are dropped, not mangled, and only a-z, 0-9 and single dashes remain.
export const slug = (name: string) =>
	name.normalize("NFKD").replace(/[^\x00-\x7f]/g, "").toLowerCase()
		.replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
