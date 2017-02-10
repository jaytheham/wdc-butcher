module wdc.carFromObj;

import wdc.car, wdc.png, wdc.tools,
	   gfm.math,
	   std.algorithm, std.stdio, std.string, std.conv, std.path;
import std.math : round;
import std.file : exists;

static class CarFromObj
{
	public static Car convert(string objFilePath)
	{
		int model = int.max, modelSection,
		    totalVertexCount = 0, sectionVertexCount = 0,
		    totalNormalCount = 0, sectionNormalCount = 0,
		    totalUvCount = 0;
		string[][] faces;
		vec2b[] sectionUvs;
		enum FIRST_LOD_INDEX = 26;
		vec3s[][3] lodVertices;
		vec3b[][3] lodNormals;
		
		Car car = new Car();
		car.modelToTextureMap.length = 0x22;
		File input = File(objFilePath, "r");

		void facesToPolygons(bool isLoD)
		{
			ushort convertVertexPointer(string indexString)
			{
				uint vertexIndex = parse!uint(indexString);
				return cast(ushort)((vertexIndex - totalVertexCount - 1) +
					(car.models[model].vertices.length - sectionVertexCount));
			}
			ushort convertNormalPointer(string indexString)
			{
				if (indexString != "")
				{
					uint normalIndex = parse!uint(indexString);
					return cast(ushort)((normalIndex - totalNormalCount - 1) +
						(car.models[model].normals.length - sectionNormalCount));
				}
				return 0;

			}
			string[] point1, point2, point3, point4;
			foreach (face; faces)
			{
				point1 = split(face[0], "/");
				point2 = split(face[1], "/");
				point3 = split(face[2], "/");
				point4 = face.length == 4 ? split(face[3], "/") : null;
				car.models[model].modelSections[modelSection].polygons ~= Car.Polygon(
					[
					isLoD ? cast(ushort)(parse!uint(point1[0]) - (totalVertexCount + 1))
					      : convertVertexPointer(point1[0]),
					isLoD ? cast(ushort)(parse!uint(point2[0]) - (totalVertexCount + 1))
					      : convertVertexPointer(point2[0]),
					isLoD ? cast(ushort)(parse!uint(point3[0]) - (totalVertexCount + 1))
					      : convertVertexPointer(point3[0]),
					point4 == null ? cast(ushort)0xFFFF
					               : (isLoD ? cast(ushort)(parse!uint(point4[0]) - (totalVertexCount + 1))
						                    : convertVertexPointer(point4[0]))
					],
					[
					sectionUvs[parse!uint(point1[1]) - totalUvCount - 1],
					sectionUvs[parse!uint(point2[1]) - totalUvCount - 1],
					sectionUvs[parse!uint(point3[1]) - totalUvCount - 1],
					point4 == null ? vec2b(cast(byte)0, cast(byte)0)
					               : sectionUvs[parse!uint(point4[1]) - totalUvCount - 1]
					],
					[
					isLoD ? cast(ushort)(parse!uint(point1[2]) - (totalNormalCount + 1))
					      : convertNormalPointer(point1[2]),
					isLoD ? cast(ushort)(parse!uint(point2[2]) - (totalNormalCount + 1))
					      : convertNormalPointer(point2[2]),
					isLoD ? cast(ushort)(parse!uint(point3[2]) - (totalNormalCount + 1))
					      : convertNormalPointer(point3[2]),
					point4 == null ? 0
					               : (isLoD ? cast(ushort)(parse!uint(point4[2]) - (totalNormalCount + 1))
						                    : convertNormalPointer(point4[2]))
					]
					);
			}
		}

		string sourcePath = dirName(objFilePath) ~ dirSeparator;
		string line;
		string[] lineParts, materialPaths;
		while((line = input.readln()) !is null)
		{
			line = chomp(line);
			
			if (line.startsWith("o "))
			{
				if (model < 2)
				{
					facesToPolygons(isLoD(modelSection));
				}
				lineParts = split(line[2..$], "-");
				if (lineParts.length >= 2)
				{
					// new section
					model = parse!int(lineParts[0]);
					modelSection = parse!int(lineParts[1]);
					if (car.models[model].modelSections.length <= modelSection)
					{
						car.models[model].modelSections.length = modelSection + 1;
					}
					totalVertexCount += sectionVertexCount;
					totalNormalCount += sectionNormalCount;
					totalUvCount += sectionUvs.length;
					sectionNormalCount = 0;
					sectionVertexCount = 0;
					sectionUvs.length = 0;
					faces.length = 0;
				}
				else if (indexOf(lineParts[0], Car.OBJ_WHEEL_ID) == 0)
				{
					foreach (i; 0..4)
					{
						line = input.readln();
						assert(line.startsWith("v "), "Less than four wheel origin vertices");
						lineParts = split(line[2..$], " ");
						car.wheelOrigins[i] = vec3f(parse!float(lineParts[0]),
						                            parse!float(lineParts[1]),
						                            parse!float(lineParts[2]));
					}
					totalVertexCount += 4;
					model = int.max;
				}
				else if (indexOf(lineParts[0], Car.OBJ_LIGHT_ID) == 0)
				{
					foreach (i; 0..4)
					{
						line = input.readln();
						assert(line.startsWith("v "), "Less than four light origin vertices");
						lineParts = split(line[2..$], " ");
						car.lightOrigins[i] = vec3f(parse!float(lineParts[0]),
						                            parse!float(lineParts[1]),
						                            parse!float(lineParts[2]));
					}
					totalVertexCount += 4;
					model = int.max;
				}
				else
				{
					writefln("WARNING: Object %s is not a recognized car part", line);
				}
			}
			else if (line.startsWith("v "))
			{
				lineParts = split(line[2..$], " ");
				void addVertex(ref vec3s[] verts)
				{
					verts ~= vec3s(cast(short)round(parse!float(lineParts[0]) * 256),
					               cast(short)round(parse!float(lineParts[1]) * 256),
					               cast(short)round(parse!float(lineParts[2]) * 256));
				}
				isLoD(modelSection) ? addVertex(lodVertices[modelSection - FIRST_LOD_INDEX])
				                    : addVertex(car.models[model].vertices);
				sectionVertexCount++;
			}
			else if (line.startsWith("vn "))
			{
				lineParts = split(line[3..$], " ");
				void addNormal(ref vec3b[] norms)
				{
					norms ~= vec3b(cast(byte)round(parse!float(lineParts[0]) * 127),
					               cast(byte)round(parse!float(lineParts[1]) * 127),
					               cast(byte)round(parse!float(lineParts[2]) * 127));
				}
				isLoD(modelSection) ? addNormal(lodNormals[modelSection - FIRST_LOD_INDEX])
				                    : addNormal(car.models[model].normals);
				sectionNormalCount++;
			}
			else if (line.startsWith("vt "))
			{
				lineParts = split(line[3..$], " ");
				sectionUvs ~= vec2b(cast(byte)round(parse!float(lineParts[0]) * 80),
				                    cast(byte)round(parse!float(lineParts[1]) * 38));
			}
			else if (line.startsWith("f "))
			{
				lineParts = split(line[2..$], " ");
				faces ~= lineParts;
			}
			else if (line.startsWith("mtllib "))
			{
				lineParts = split(line, " ");
				if (isAbsolute(lineParts[1]))
				{
					materialPaths = texturePathsFromMtl(lineParts[1], "");
				}
				else
				{
					string materialLibraryPath = sourcePath ~ lineParts[1];
					materialPaths = texturePathsFromMtl(materialLibraryPath, sourcePath);
				}
				foreach (path; materialPaths)
				{
					if (path != "")
					{
						car.textures ~= Png.pngToWdcTexture(path)[0];
					}
					else
					{
						// it seems all 'missing' textures can be 8
						// but only some can be 0, how to tell?
						car.textures ~= new ubyte[8];
					}
				}
			}
			else if (line.startsWith("usemtl "))
			{
				lineParts = split(line, " ");
				int materialIndex = parse!int(lineParts[1]);
				if (model == 0)
				{
					car.modelToTextureMap[modelSection] = materialIndex;
					if (materialPaths[materialIndex] != "")
					{
						car.paletteSets[0][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcTexture(materialPaths[materialIndex])[1];

						string altPaletteTexturePath = materialPaths[materialIndex][0..$-20] ~ "set1" ~ materialPaths[materialIndex][$-16..$];
						car.paletteSets[1][Car.MODEL_TO_PALETTE[modelSection]] = exists(altPaletteTexturePath)
						                                                       ? Png.pngToWdcTexture(altPaletteTexturePath)[1]
						                                                       : car.paletteSets[0][Car.MODEL_TO_PALETTE[modelSection]];

						altPaletteTexturePath = materialPaths[materialIndex][0..$-20] ~ "set2" ~ materialPaths[materialIndex][$-16..$];
						car.paletteSets[2][Car.MODEL_TO_PALETTE[modelSection]] = exists(altPaletteTexturePath)
						                                                       ? Png.pngToWdcTexture(altPaletteTexturePath)[1]
						                                                       : car.paletteSets[0][Car.MODEL_TO_PALETTE[modelSection]];
					}
				} else if (model == 1)
				{
					car.modelToTextureMap[Car.PartNames.fake_wheels] = materialIndex;
				}
			}
		}
		facesToPolygons(isLoD(modelSection));
		totalVertexCount += sectionVertexCount;
		totalNormalCount += sectionNormalCount;
		totalUvCount += sectionUvs.length;

		snapLoDsToNearest(car, lodVertices, lodNormals);
		shiftWheelTextureMapping(car.models[1].modelSections[0].polygons);
		
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "set0_wheel_0.png")[0];
		car.modelToTextureMap[30] = car.textures.length - 1;
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "set0_wheel_1.png")[0];
		car.modelToTextureMap[31] = car.textures.length - 1;
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "set0_wheel_2.png")[0];
		car.modelToTextureMap[32] = car.textures.length - 1;
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "set0_wheel_3.png")[0];
		car.modelToTextureMap[33] = car.textures.length - 1;
		car.paletteSets[0][Car.MODEL_TO_PALETTE[30]] = Png.pngToWdcTexture(sourcePath ~ "set0_wheel_0.png")[1];
		car.paletteSets[1][Car.MODEL_TO_PALETTE[30]] = Png.pngToWdcTexture(sourcePath ~ "set1_wheel_0.png")[1];
		car.paletteSets[2][Car.MODEL_TO_PALETTE[30]] = Png.pngToWdcTexture(sourcePath ~ "set2_wheel_0.png")[1];

		int litHeadlightPalleteNum = Car.MODEL_TO_PALETTE[Car.PartNames.headlight_l] + 1;
		int litHeadlightTextureNum = car.modelToTextureMap[Car.PartNames.headlight_l];
		string headlightLitTexturePath = sourcePath ~ format("set0_tex%.2d_pal05.png", litHeadlightTextureNum);
		car.paletteSets[0][litHeadlightPalleteNum] = Png.pngToWdcTexture(headlightLitTexturePath)[1];
		headlightLitTexturePath = sourcePath ~ format("set1_tex%.2d_pal05.png", litHeadlightTextureNum);
		car.paletteSets[1][litHeadlightPalleteNum] = Png.pngToWdcTexture(headlightLitTexturePath)[1];
		headlightLitTexturePath = sourcePath ~ format("set2_tex%.2d_pal05.png", litHeadlightTextureNum);
		car.paletteSets[1][litHeadlightPalleteNum] = Png.pngToWdcTexture(headlightLitTexturePath)[1];

		int litTaillightPalleteNum = Car.MODEL_TO_PALETTE[Car.PartNames.taillight_l] + 1;
		int litTaillightTextureNum = car.modelToTextureMap[Car.PartNames.taillight_l];
		string taillightLitTexturePath = sourcePath ~ format("set0_tex%.2d_pal07.png", litTaillightTextureNum);
		car.paletteSets[0][litTaillightPalleteNum] = Png.pngToWdcTexture(taillightLitTexturePath)[1];
		taillightLitTexturePath = sourcePath ~ format("set1_tex%.2d_pal07.png", litTaillightTextureNum);
		car.paletteSets[1][litTaillightPalleteNum] = Png.pngToWdcTexture(taillightLitTexturePath)[1];
		taillightLitTexturePath = sourcePath ~ format("set2_tex%.2d_pal07.png", litTaillightTextureNum);
		car.paletteSets[2][litTaillightPalleteNum] = Png.pngToWdcTexture(taillightLitTexturePath)[1];
		car.insertedPaletteIndices = [0,1,2,3,4,5,6,7];
		input.close();
		parseSettings(sourcePath ~ "carSettings.txt", car);
		car.generateBinaries();
		return car;
	}

	private static void parseSettings(string settingsFilePath, Car car)
	{
		File input = File(settingsFilePath, "r");
		string line;
		string[] lineParts;

		while((line = input.readln()) !is null)
		{
			lineParts = split(line, ",");
			lineParts[2] = strip(lineParts[2]);
			car.settings[parse!int(lineParts[0])] = parse!float(lineParts[2]);
		}
	}

	private static bool isLoD(uint sectionNumber)
	{
		return sectionNumber == 26 || sectionNumber == 27 || sectionNumber == 28;
	}

	private static void snapLoDsToNearest(ref Car car, ref vec3s[][3] lodVertices, ref vec3b[][3] lodNormals)
	{
		enum FIRST_LOD_INDEX = 26;
		float distanceBetween(vec3s a, vec3s b)
		{
			import std.math;
			return sqrt(cast(float)(pow((b.x - a.x), 2) + pow((b.y - a.y), 2) + pow((b.z - a.z), 2)));
		}
		ushort findNearestPoint(vec3s toVertex)
		{
			import std.math : abs;
			uint closestIndex;
			float minDistance = 100_000.0;
			float currentDistance;
			foreach (fromIndex, fromVertex; car.models[0].vertices)
			{
				currentDistance = distanceBetween(fromVertex, toVertex);
				if (abs(currentDistance) < minDistance)
				{
					minDistance = currentDistance;
					closestIndex = fromIndex;
					if (minDistance == 0.0)
					{
						break;
					}
				}
			}
			return cast(ushort)closestIndex;
		}
		ushort findNearestNormal(vec3b source)
		{
			import std.math : PI;
			vec3f lodNormal = vec3f(source.x, source.y, source.z);
			uint closestIndex;
			double minDistance = 100_000.0;
			double currentDistance;
			foreach (carIndex, carNormal; car.models[0].normals)
			{
				currentDistance = angleBetween(lodNormal, vec3f(carNormal.x, carNormal.y, carNormal.z)) * (180.0 / PI);
				if (currentDistance < minDistance)
				{
					minDistance = currentDistance;
					closestIndex = carIndex;
					if (minDistance == 0.0)
					{
						break;
					}
				}
			}
			return cast(ushort)closestIndex;
		}
		foreach (lodNumber; 0..3)
		{
			foreach (ref polygon; car.models[0].modelSections[lodNumber + FIRST_LOD_INDEX].polygons)
			{
				foreach (ref vertexIndex; polygon.vertexIndices)
				{
					if (vertexIndex != 0xFFFF)
					{
						vertexIndex = findNearestPoint(lodVertices[lodNumber][vertexIndex]);
					}
				}
				foreach (ref normalIndex; polygon.normalIndices)
				{
					normalIndex = findNearestNormal(lodNormals[lodNumber][normalIndex]);
				}
			}
		}
	}

	private static void shiftWheelTextureMapping(ref Car.Polygon[] polygons)
	{
		// Assumes polys are mapped directly on top of the texture, not way off somewhere
		bool notOffset = false;
		foreach (Car.Polygon polygon; polygons)
		{
			foreach (vec2b uv; polygon.textureCoordinates)
			{
				if (uv.y < 38)
				{
					notOffset = true;
					break;
				}
			}
			if (notOffset)
			{
				break;
			}
		}
		if (notOffset)
		{
			foreach (ref Car.Polygon polygon; polygons)
			{
				foreach (ref vec2b uv; polygon.textureCoordinates)
				{
					uv.y += (38 * 2);
				}
			}
		}
	}

	private static string[] texturePathsFromMtl(string mtlLibraryPath, string path)
	{
		import std.conv, std.string;

		string[] texturePaths = new string[0x20], lineParts;
		int textureNum;
		string line;
		File input = File(mtlLibraryPath, "r");
		while((line = input.readln()) !is null)
		{
			if (line.startsWith("newmtl "))
			{
				lineParts = split(line, " ");
				textureNum = parse!int(lineParts[1]);
			}
			if (line.startsWith("map_Kd "))
			{
				lineParts = split(line, "map_Kd ");
				texturePaths[textureNum] = path ~ chomp(lineParts[1]);
			}
		}
		input.close();
		return texturePaths;
	}


}