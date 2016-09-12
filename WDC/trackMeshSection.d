module wdc.trackMeshSection;

import std.stdio,
	   gfm.math,
	   wdc.tools;

class TrackMeshSection
{
	struct Vertex
	{
		short Z;
		short X;
		short Y;
	}

	struct Polygon
	{
		int unknown_1;
		ubyte textureIndex;
		ubyte unknown_2;
		ubyte unknown_3;
		ubyte unknown_4;
		ushort vertexIndexOne;
		ushort vertexIndexTwo;
		ushort vertexIndexThree;
		ushort vertexIndexFour;
		ushort uvIndexOne;
		ushort uvIndexTwo;
		ushort uvIndexThree;
		ushort uvIndexFour;
		// I am assuming these are shorts, bytes would work just as well, are the upper bytes ever non-zero?
		ushort vertexOneColourIndex;
		ushort vertexTwoColourIndex;
		ushort vertexThreeColourIndex;
		ushort vertexFourColourIndex;
	}

	// Don't know if these are actually signed
	struct UV
	{
		short u;
		short v;
	}

	//struct Colour
	//{
	//	ubyte R;
	//	ubyte G;
	//	ubyte B;
	//	ubyte A;
	//}

	struct ModelInfo
	{
		Vertex[] vertices;
		Polygon[] polygons;
		UV[] uvs;
		vec4ub[] colours;
		int originZ;
		int originX;
		int originY;
	}

	ubyte[] binary;
	ModelInfo[] models;
	ubyte sectionsToDrawAhead;
	ubyte sectionsToDrawBehind;

	this(ubyte[] newSectionBinary, int sectionInfo)
	{
		int modelInfo = sectionInfo + 8;
		int nextModelInfo = newSectionBinary.readInt(sectionInfo + 0x18);
		int numAdditionalModelInfo = newSectionBinary[sectionInfo + 0x1e];

		//assert(newSectionBinary.readInt(sectionInfo) == 0x419, "419");
		//assert(newSectionBinary.readInt(sectionInfo + 4) == 0x28fc, "28fc");
		// These are different for different tracks, check do they get overwritten, or added to?

		int modelPartsInfo;
		int vertices, polygons, uvs, colours;
		int vertexCount, polygonCount, uvCount, colourCount;

		sectionsToDrawAhead = newSectionBinary[sectionInfo + 0x1c];
		sectionsToDrawBehind = newSectionBinary[sectionInfo + 0x1d];
		
		while (numAdditionalModelInfo >= 0)
		{
			modelPartsInfo = newSectionBinary.readInt(modelInfo);

			vertexCount = newSectionBinary.readInt(modelPartsInfo + 4);
			polygonCount = newSectionBinary.readInt(modelPartsInfo + 12);
			uvCount = newSectionBinary.readInt(modelPartsInfo + 20);
			colourCount = newSectionBinary.readInt(modelPartsInfo + 28);

			assert(newSectionBinary[modelInfo + 7] == 0, "Not 0");
			assert(newSectionBinary[modelInfo + 11] == 0, "Not 0");
			assert(newSectionBinary[modelInfo + 15] == 0, "Not 0");

			models ~= ModelInfo(new Vertex[vertexCount],
			                               new Polygon[polygonCount],
			                               new UV[uvCount],
			                               new vec4ub[colourCount],
			                               newSectionBinary.readInt(modelInfo + 4),
			                               newSectionBinary.readInt(modelInfo + 8),
			                               newSectionBinary.readInt(modelInfo + 12)
			                              );

			vertices = newSectionBinary.readInt(modelPartsInfo);
			foreach (index; 0..vertexCount)
			{
				models[$ - 1].vertices[index] = Vertex(
				                                                  newSectionBinary.readShort(vertices + (index * 6)),
				                                                  newSectionBinary.readShort(vertices + 2 + (index * 6)),
				                                                  newSectionBinary.readShort(vertices + 4 + (index * 6))
				                                                 );
			}

			polygons = newSectionBinary.readInt(modelPartsInfo + 8);
			foreach(index; 0..polygonCount)
			{
				models[$ - 1].polygons[index] = Polygon(
				                                                   newSectionBinary.readInt(polygons + (index * 32)),
				                                                   newSectionBinary[polygons + 4 + (index * 32)],
				                                                   newSectionBinary[polygons + 5 + (index * 32)],
				                                                   newSectionBinary[polygons + 6 + (index * 32)],
				                                                   newSectionBinary[polygons + 7 + (index * 32)],
				                                                   // Vertices
				                                                   newSectionBinary.readUshort(polygons + 8 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 10 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 12 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 14 + (index * 32)),
				                                                   // UVs
				                                                   newSectionBinary.readUshort(polygons + 16 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 18 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 20 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 22 + (index * 32)),
				                                                   // Colours
				                                                   newSectionBinary.readUshort(polygons + 24 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 26 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 28 + (index * 32)),
				                                                   newSectionBinary.readUshort(polygons + 30 + (index * 32))
				                                                  );
			}

			uvs = newSectionBinary.readInt(modelPartsInfo + 16);
			foreach(index; 0..uvCount)
			{
				models[$ - 1].uvs[index] = UV(newSectionBinary.readShort(uvs + (index * 4)),
				                                         newSectionBinary.readShort(uvs + 2 + (index * 4)));
			}

			colours = newSectionBinary.readInt(modelPartsInfo + 24);
			foreach(index; 0..colourCount)
			{
				models[$ - 1].colours[index] = vec4ub(
				                                                 newSectionBinary[colours + (index * 4)],
				                                                 newSectionBinary[colours + 1 + (index * 4)],
				                                                 newSectionBinary[colours + 2 + (index * 4)],
				                                                 newSectionBinary[colours + 3 + (index * 4)]
				                                                );
			}
			modelInfo = nextModelInfo;
			nextModelInfo += 0x10;
			
			numAdditionalModelInfo -= 1;
		}
	}
}