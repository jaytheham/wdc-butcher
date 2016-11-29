module wdc.carFromObj;

import wdc.car, wdc.png, wdc.tools,
	
	   gfm.math,

	   std.algorithm, std.stdio, std.string, std.conv, std.math : round;

static class CarFromObj
{
	public static Car convert(string objFilePath)
	{
		int model = 0xFFFF, modelSection,
		    totalVertexCount = 0, sectionVertexCount = 0,
		    totalNormalCount = 0, sectionNormalCount = 0,
		    totalUvCount = 0;
		string line;
		string[][] faces;
		string[] lineParts, materialPaths;
		vec2b[] sectionUvs;

		enum FIRST_LOD_INDEX = 26;
		vec3s[][3] lodVertices;
		vec3b[][3] lodNormals;
		
		Car car = new Car();
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
				uint normalIndex = parse!uint(indexString);
				return cast(ushort)((normalIndex - totalNormalCount - 1) +
					(car.models[model].normals.length - sectionNormalCount));
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

		while((line = input.readln()) !is null)
		{
			line = chomp(line);
			
			if (line.startsWith("o "))
			{
				if (model != 0xFFFF)
				{
					facesToPolygons(isLoD(modelSection));
				}
				lineParts = split(line[2..$], "-");
				if (lineParts.length >= 2)
				{
					// new section
					model = parse!int(lineParts[0]);
					modelSection = parse!int(lineParts[1]);
					while (car.models[model].modelSections.length <= modelSection)
					{
						car.models[model].modelSections ~= Car.ModelSection();
					}
					totalVertexCount += sectionVertexCount;
					totalNormalCount += sectionNormalCount;
					totalUvCount += sectionUvs.length;
					sectionNormalCount = 0;
					sectionVertexCount = 0;
					sectionUvs.length = 0;
					faces.length = 0;
				}
				else if (lineParts[0] == Car.OBJ_WHEEL_ID)
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
					model = 0xFFFF;
				}
				else if (lineParts[0] == Car.OBJ_LIGHT_ID)
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
					model = 0xFFFF;
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
				if (canFind(lineParts[1], '\\') || canFind(lineParts[1], '/')) // Absolute path, hopefully
				{
					materialPaths = texturePathsFromMtl(lineParts[1]);
				}
				else
				{
					int folderEndIndex = lastIndexOf(objFilePath, '/') != -1 ? lastIndexOf(objFilePath, '/') : lastIndexOf(objFilePath, '\\');
					string materialLibraryPath = objFilePath[0..folderEndIndex + 1] ~ lineParts[1];
					materialPaths = texturePathsFromMtl(materialLibraryPath);
				}
				foreach (path; materialPaths)
				{
					if (path != "")
					{
						car.textures ~= Png.pngToWdcTexture(path);
					}
					else
					{
						// it seems all 'missing' textures can be 8
						// but only some can be 0, how to tell?
						car.textures ~= new ubyte[8];
					}
				}
			}
			else if (line.startsWith("usemtl ") && model == 0)
			{
				lineParts = split(line, " ");
				int materialIndex = parse!int(lineParts[1]);
				car.modelToTextureMap[modelSection] = materialIndex;
				car.paletteSets[0][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcPalette(materialPaths[materialIndex]);

				int fileNameStart = lastIndexOf(materialPaths[materialIndex], '/');
				fileNameStart = fileNameStart == -1 ? lastIndexOf(materialPaths[materialIndex], '\\') : fileNameStart;
				fileNameStart = fileNameStart == -1 ? 1 : fileNameStart + 1;
				string sourcePath = materialPaths[materialIndex][0..fileNameStart];
				string fileEnd = materialPaths[materialIndex][fileNameStart + 1..$];
				car.paletteSets[1][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcPalette(sourcePath ~ "1" ~ fileEnd);
				car.paletteSets[2][Car.MODEL_TO_PALETTE[modelSection]] = Png.pngToWdcPalette(sourcePath ~ "2" ~ fileEnd);
			}
		}
		facesToPolygons(isLoD(modelSection));
		totalVertexCount += sectionVertexCount;
		totalNormalCount += sectionNormalCount;
		totalUvCount += sectionUvs.length;

		updateLoDs(car, lodVertices, lodNormals);
		
		car.modelToTextureMap[18] = 14; // static wheel
		int folderEndIndex = lastIndexOf(objFilePath, '/') != -1 ? lastIndexOf(objFilePath, '/') : lastIndexOf(objFilePath, '\\');
		string sourcePath = folderEndIndex == -1 ? "" : objFilePath[0..folderEndIndex + 1];
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car22_0.png");
		car.paletteSets[0][Car.MODEL_TO_PALETTE[0x1E]] = Png.pngToWdcPalette(sourcePath ~ "0_car22_0.png");
		car.paletteSets[1][Car.MODEL_TO_PALETTE[0x1E]] = Png.pngToWdcPalette(sourcePath ~ "1_car22_0.png");
		car.paletteSets[2][Car.MODEL_TO_PALETTE[0x1E]] = Png.pngToWdcPalette(sourcePath ~ "2_car22_0.png");
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car23_0.png");
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car24_0.png");
		car.textures ~= Png.pngToWdcTexture(sourcePath ~ "0_car25_0.png");
		car.modelToTextureMap[0x1E] = 22;
		car.modelToTextureMap[0x1F] = 23;
		car.modelToTextureMap[0x20] = 24;
		car.modelToTextureMap[0x21] = 25;

		car.insertedPaletteIndices = [0,1,2,3,4,5,6,7];
		input.close();
		car.generateBinaries();
		return car;
	}

	private static bool isLoD(uint sectionNumber)
	{
		return sectionNumber == 26 || sectionNumber == 27 || sectionNumber == 28;
	}

	private static void updateLoDs(ref Car car, ref vec3s[][3] lodVertices, ref vec3b[][3] lodNormals)
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
			float distance = 100_000.0;
			float temp;
			foreach (fromIndex, fromVertex; car.models[0].vertices)
			{
				temp = distanceBetween(fromVertex, toVertex);
				if (abs(temp) < distance)
				{
					distance = temp;
					closestIndex = fromIndex;
					if (distance == 0.0)
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
			double distance = 100_000.0;
			double temp;
			foreach (carIndex, carNormal; car.models[0].normals)
			{
				temp = angleBetween(lodNormal, vec3f(carNormal.x, carNormal.y, carNormal.z)) * (180.0 / PI);
				if (temp < distance)
				{
					distance = temp;
					closestIndex = carIndex;
					if (distance == 0.0)
					{
						break;
					}
				}
			}
			return cast(ushort)closestIndex;
		}
		foreach (lod; 0..3)
		{
			foreach (ref polygon; car.models[0].modelSections[lod + FIRST_LOD_INDEX].polygons)
			{
				foreach (ref vertexIndex; polygon.vertexIndices)
				{
					if (vertexIndex != 0xFFFF)
					{
						vertexIndex = findNearestPoint(lodVertices[lod][vertexIndex]);
					}
				}
				foreach (ref normalIndex; polygon.normalIndices)
				{
					normalIndex = findNearestNormal(lodNormals[lod][normalIndex]);
				}
			}
		}
	}

	private static string[] texturePathsFromMtl(string mtlLibraryPath)
	{
		import std.conv, std.string;

		string[] texturePaths = new string[0x16], lineParts;
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
				texturePaths[textureNum] = chomp(lineParts[1]);
			}
		}
		input.close();
		return texturePaths;
	}


}