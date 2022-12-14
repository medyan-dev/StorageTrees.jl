using StructArrays

"""
Convert a nested StructArray into a ZGroup
All propertynames must be Integer or Symbol.
The data can be loaded back with [`read_nested_struct_array!`](@ref)
Any subdata with sizeof(eltype) == 0 will be ignored
"""
function write_nested_struct_array(data::StructArray)::ZGroup
    group = ZGroup()
    for (i, pname) in enumerate(propertynames(data))
        (pname isa Union{Integer,Symbol}) || error("all propertynames must be Integer or Symbol")
        subdata = getproperty(data,pname)
        if subdata isa StructArray
            subgroup = write_nested_struct_array(subdata)
            #note, the group cannot be called string(pname) because it may not be ASCII
            attrs(subgroup)["name"] = string(pname)
            group["$i"] = subgroup
        else
            if sizeof(eltype(subdata)) != 0
                #TODO add compressor options, maybe as some task local context?
                group["$i"] = subdata
                attrs(group["$i"])["name"] = string(pname)
            end
        end
    end
    group
end


"""
load a nested StructArray from a ZGroup into a preallocated StructArray.
The properties saved in the group will over write data in the StructArray with the same propertynames
Loading is based purely on the "name" attribute which will be parsed
as an Int or Symbol property name.
subgroups correspond to a nested StructArray.
"""
function read_nested_struct_array!(data::StructArray, group::ZGroup)
    for child in values(children(group))
        namerepr = attrs(child)["name"]
        !isempty(namerepr) || error("property name empty")
        pname = if isdigit(namerepr[begin]) # Assume property name is an Int
            parse(Int, namerepr)
        else # Assume property name is a symbol
            Symbol(namerepr)
        end
        if child isa ZArray
            newchilddata = getarray(child)
            oldchilddata = getproperty(data,pname)
            axes(newchilddata) == axes(oldchilddata) || error("data is $(axes(data)), ZGroup is $(axes(newchilddata))")
            copy!(oldchilddata,newchilddata)
        elseif child isa ZGroup
            oldchilddata = getproperty(data,pname)
            read_nested_struct_array!(oldchilddata, child)
        else
            error("unreachable")
        end
    end
end


"""
Print the difference between the ZGroups
"""
function print_diff(io, group1::ZGroup, group2::ZGroup, group1name="group1", group2name="group2", header="", ignorename=Returns(false))
    #check both groups have same keys
    ks1 = Set(keys(group1))
    ks2 = Set(keys(group2))
    diffks1 = sort(collect(setdiff(ks1,ks2)))
    diffks2 = sort(collect(setdiff(ks2,ks1)))
    foreach(diffks1) do diffk
        ignorename(diffk) && return
        println(io,"\"$header$diffk\" in $group1name but not in $group2name")
    end
    foreach(diffks2) do diffk
        ignorename(diffk) && return
        println(io,"\"$header$diffk\" in $group2name but not in $group1name")
    end
    #check attributes are equal
	print_attrs_diff(io, group1, group2, group1name, group2name, header, ignorename)
    sharedkeys= sort(collect(ks1 ??? ks2))
    foreach(sharedkeys) do key
        ignorename(key) && return
        print_diff(io, group1[key], group2[key], group1name, group2name, header*key*"/", ignorename)
    end
end

function print_diff(io, group1::ZArray, group2::ZArray, group1name="group1", group2name="group2", header="", ignorename=Returns(false))
    print_attrs_diff(io, group1, group2, group1name, group2name, header, ignorename)
    data1 = getarray(group1)
    data2 = getarray(group2)
    if !isequal(data1,data2)
		for (groupname,data) in [(group1name,data1),(group2name,data2)]
			if isempty(header)
				println(io,"getarray($groupname):")
			else
				println(io,"getarray($groupname[\"$header\"]):")
			end
			show(io,data)
			println(io)
		end
    end
end

function print_diff(io, group1::Union{ZGroup, ZArray}, group2::Union{ZGroup, ZArray}, group1name="group1", group2name="group2", header="", ignorename=Returns(false))
	if isempty(header)
		println(io, "$group1name isa $(typeof(group1)), $group2name isa $(typeof(group2))")
	else
		println(io, "$group1name[\"$header\"] isa $(typeof(group1)), $group2name[\"$header\"] isa $(typeof(group2))")
	end
end

function print_attrs_diff(io, group1::Union{ZGroup, ZArray}, group2::Union{ZGroup, ZArray}, group1name="group1", group2name="group2", header="", ignorename=Returns(false))
	for (groupaname,groupa,groupb) in [(group1name,group1,group2),(group2name,group2,group1)]
		diffas = sort(collect(setdiff(attrs(groupa),attrs(groupb))); by=(x->x[1]))
	    foreach(diffas) do (k,v)
            ignorename(k) && return
			if isempty(header)
				print(io,"attrs($groupaname)")
			else
				print(io,"attrs($groupaname[\"$header\"])")
			end
			print(io,"[\"$k\"] is ")
			show(io, v)
			println(io)
	    end
	end
end


"""
show_diff(;group1, group2)
"""
function show_diff(ignorename=Returns(false);kwargs...)
    length(kwargs) == 2 || error("must compare two groups")
    group1name = string(keys(kwargs)[1])
    group2name = string(keys(kwargs)[2])
    maxnamewidth = max(textwidth(group1name),textwidth(group2name))
    group1name = lpad(group1name, maxnamewidth)
    group2name = lpad(group2name, maxnamewidth)
    Docs.Text(io->print_diff(io, kwargs[1], kwargs[2], group1name, group2name, "", ignorename))
end


"""
@test_equal group1 group2 -> let s = sprint(io->print_diff(io,group1, group2,"group1","group2")); print(s); @test isempty(s)==true; end
"""
macro test_equal(group1,group2,ignorename=:(Returns(false)))
    group1name = string(group1)
    group2name = string(group2)
    maxnamewidth = max(textwidth(group1name),textwidth(group2name))
    group1name = lpad(group1name, maxnamewidth)
    group2name = lpad(group2name, maxnamewidth)
    esc(quote
        let diff = sprint(io->MEDYAN.StorageTrees.print_diff(io,$group1, $group2, $group1name, $group2name, "", $ignorename))
            print(diff)
            @test isempty(diff) == true
        end
    end)
end