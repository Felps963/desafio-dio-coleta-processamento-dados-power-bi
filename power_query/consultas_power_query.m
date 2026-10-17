section Section1;

shared Departamentos = let
    Fonte = MySQL.Database("localhost", "azure_company", [ReturnSingleDatabase = true]),
    departament = Fonte{[Schema = "azure_company", Item = "departament"]}[Data],
    // O conector MySQL traz colunas de relacionamento (azure_company.xxx); ficam só as colunas da tabela
    Colunas = Table.SelectColumns(departament, {"Dname", "Dnumber", "Mgr_ssn", "Mgr_start_date", "Dept_create_date"}),
    // 1. Cabeçalhos e tipos de dados
    Tipos = Table.TransformColumnTypes(Colunas, {
        {"Dname", type text}, {"Dnumber", Int64.Type}, {"Mgr_ssn", type text},
        {"Mgr_start_date", type date}, {"Dept_create_date", type date}}),
    // 2. Departamento sem gerente: nesta base todos têm Mgr_ssn (a coluna é NOT NULL).
    //    Se aparecer algum, a lacuna é preenchida com o gerente do departamento 1 (Headquarters).
    SemGerentePreenchido = Table.ReplaceValue(Tipos, null, "888665555", Replacer.ReplaceValue, {"Mgr_ssn"}),
    // 3. Nome do gerente do departamento
    employee = Fonte{[Schema = "azure_company", Item = "employee"]}[Data],
    MesclaGerente = Table.NestedJoin(SemGerentePreenchido, {"Mgr_ssn"}, employee, {"Ssn"}, "G", JoinKind.LeftOuter),
    ExpandeGerente = Table.ExpandTableColumn(MesclaGerente, "G", {"Fname", "Lname"}, {"G.Fname", "G.Lname"}),
    GerenteNome = Table.CombineColumns(ExpandeGerente, {"G.Fname", "G.Lname"}, Combiner.CombineTextByDelimiter(" ", QuoteStyle.None), "Gerente do Departamento"),
    Renomeado = Table.RenameColumns(GerenteNome, {
        {"Dname", "Departamento"}, {"Mgr_start_date", "Gerente Desde"}, {"Dept_create_date", "Data de Criação"}}),
    Ordenado = Table.ReorderColumns(Renomeado, {"Dnumber", "Departamento", "Mgr_ssn", "Gerente do Departamento", "Gerente Desde", "Data de Criação"})
in
    Ordenado;

shared Colaboradores = let
    Fonte = MySQL.Database("localhost", "azure_company", [ReturnSingleDatabase = true]),
    employee = Fonte{[Schema = "azure_company", Item = "employee"]}[Data],
    // O conector MySQL traz colunas de relacionamento (azure_company.xxx); ficam só as colunas da tabela
    Colunas = Table.SelectColumns(employee, {"Fname", "Minit", "Lname", "Ssn", "Bdate", "Address", "Sex", "Salary", "Super_ssn", "Dno"}),
    // 1. Cabeçalhos e tipos (Salary como número decimal = double)
    Tipos = Table.TransformColumnTypes(Colunas, {
        {"Fname", type text}, {"Minit", type text}, {"Lname", type text}, {"Ssn", type text},
        {"Bdate", type date}, {"Address", type text}, {"Sex", type text}, {"Salary", type number},
        {"Super_ssn", type text}, {"Dno", Int64.Type}}),
    // 2. Mescla com departamentos (base = employee -> junção externa esquerda:
    //    mantém todos os colaboradores, mesmo que algum não tenha departamento)
    MesclaDept = Table.NestedJoin(Tipos, {"Dno"}, Departamentos, {"Dnumber"}, "Dept", JoinKind.LeftOuter),
    ExpandeDept = Table.ExpandTableColumn(MesclaDept, "Dept", {"Departamento"}, {"Departamento"}),
    // 3. Junção colaborador x gerente (self join pelo Super_ssn)
    MesclaGerente = Table.NestedJoin(ExpandeDept, {"Super_ssn"}, Tipos, {"Ssn"}, "Ger", JoinKind.LeftOuter),
    ExpandeGerente = Table.ExpandTableColumn(MesclaGerente, "Ger", {"Fname", "Lname"}, {"Ger.Fname", "Ger.Lname"}),
    // Super_ssn nulo = colaborador sem gerente (James Borg é o diretor, topo da hierarquia)
    Gerente = Table.AddColumn(ExpandeGerente, "Gerente",
        each if [Ger.Fname] = null then "Sem gerente (diretoria)" else [Ger.Fname] & " " & [Ger.Lname], type text),
    // 4. Nome + Sobrenome em uma coluna só
    Nome = Table.CombineColumns(Gerente, {"Fname", "Lname"}, Combiner.CombineTextByDelimiter(" ", QuoteStyle.None), "Colaborador"),
    // 5. Separar coluna complexa: Address = Número-Rua-Cidade-Estado
    SplitNumero = Table.SplitColumn(Nome, "Address", Splitter.SplitTextByEachDelimiter({"-"}, QuoteStyle.None, false), {"Número", "Resto"}),
    SplitEstado = Table.SplitColumn(SplitNumero, "Resto", Splitter.SplitTextByEachDelimiter({"-"}, QuoteStyle.None, true), {"Resto2", "Estado"}),
    SplitCidade = Table.SplitColumn(SplitEstado, "Resto2", Splitter.SplitTextByEachDelimiter({"-"}, QuoteStyle.None, true), {"Rua", "Cidade"}),
    RuaLimpa = Table.ReplaceValue(SplitCidade, "-", " ", Replacer.ReplaceText, {"Rua"}),
    TiposEndereco = Table.TransformColumnTypes(RuaLimpa, {{"Número", Int64.Type}, {"Rua", type text}, {"Cidade", type text}, {"Estado", type text}}),
    Sexo = Table.ReplaceValue(Table.ReplaceValue(TiposEndereco, "M", "Masculino", Replacer.ReplaceValue, {"Sex"}), "F", "Feminino", Replacer.ReplaceValue, {"Sex"}),
    // 6. Remover colunas desnecessárias
    RemoveColunas = Table.RemoveColumns(Sexo, {"Minit", "Ger.Fname", "Ger.Lname"}),
    Renomeado = Table.RenameColumns(RemoveColunas, {{"Bdate", "Data de Nascimento"}, {"Sex", "Sexo"}, {"Salary", "Salário"}}),
    Ordenado = Table.ReorderColumns(Renomeado, {"Ssn", "Colaborador", "Sexo", "Data de Nascimento", "Salário", "Dno", "Departamento", "Super_ssn", "Gerente", "Número", "Rua", "Cidade", "Estado"})
in
    Ordenado;

shared #"Colaboradores por Gerente" = let
    // Agrupamento: quantos colaboradores cada gerente tem
    Fonte = Colaboradores,
    ComGerente = Table.SelectRows(Fonte, each [Super_ssn] <> null),
    Agrupado = Table.Group(ComGerente, {"Gerente"}, {
        {"Qtd. Colaboradores", each Table.RowCount(_), Int64.Type},
        {"Folha Salarial da Equipe", each List.Sum([Salário]), type number}}),
    Ordenado = Table.Sort(Agrupado, {{"Qtd. Colaboradores", Order.Descending}})
in
    Ordenado;

shared #"Departamentos e Locais" = let
    Fonte = MySQL.Database("localhost", "azure_company", [ReturnSingleDatabase = true]),
    dept_locations = Fonte{[Schema = "azure_company", Item = "dept_locations"]}[Data],
    Colunas = Table.SelectColumns(dept_locations, {"Dnumber", "Dlocation"}),
    Tipos = Table.TransformColumnTypes(Colunas, {{"Dnumber", Int64.Type}, {"Dlocation", type text}}),
    MesclaDept = Table.NestedJoin(Tipos, {"Dnumber"}, Departamentos, {"Dnumber"}, "Dept", JoinKind.LeftOuter),
    ExpandeDept = Table.ExpandTableColumn(MesclaDept, "Dept", {"Departamento", "Mgr_ssn"}, {"Departamento", "Mgr_ssn"}),
    CopiaLocal = Table.DuplicateColumn(ExpandeDept, "Dlocation", "Cidade"),
    // Mesclar colunas Local + Departamento: cada combinação departamento-local vira um valor único
    DeptLocal = Table.CombineColumns(CopiaLocal, {"Dlocation", "Departamento"}, Combiner.CombineTextByDelimiter(" ", QuoteStyle.None), "Departamento_Local"),
    Ordenado = Table.ReorderColumns(DeptLocal, {"Departamento_Local", "Dnumber", "Mgr_ssn", "Cidade"})
in
    Ordenado;

shared Projetos = let
    Fonte = MySQL.Database("localhost", "azure_company", [ReturnSingleDatabase = true]),
    project = Fonte{[Schema = "azure_company", Item = "project"]}[Data],
    works_on = Fonte{[Schema = "azure_company", Item = "works_on"]}[Data],
    Colunas = Table.SelectColumns(project, {"Pname", "Pnumber", "Plocation", "Dnum"}),
    Tipos = Table.TransformColumnTypes(Colunas, {{"Pname", type text}, {"Pnumber", Int64.Type}, {"Plocation", type text}, {"Dnum", Int64.Type}}),
    // Número de horas por projeto (soma de works_on.Hours)
    HorasTipos = Table.TransformColumnTypes(Table.SelectColumns(works_on, {"Essn", "Pno", "Hours"}), {{"Pno", Int64.Type}, {"Hours", type number}}),
    HorasPorProjeto = Table.Group(HorasTipos, {"Pno"}, {
        {"Total de Horas", each List.Sum([Hours]), type number},
        {"Qtd. Colaboradores", each Table.RowCount(_), Int64.Type}}),
    MesclaHoras = Table.NestedJoin(Tipos, {"Pnumber"}, HorasPorProjeto, {"Pno"}, "H", JoinKind.LeftOuter),
    ExpandeHoras = Table.ExpandTableColumn(MesclaHoras, "H", {"Total de Horas", "Qtd. Colaboradores"}),
    MesclaDept = Table.NestedJoin(ExpandeHoras, {"Dnum"}, Departamentos, {"Dnumber"}, "Dept", JoinKind.LeftOuter),
    ExpandeDept = Table.ExpandTableColumn(MesclaDept, "Dept", {"Departamento"}),
    Renomeado = Table.RenameColumns(ExpandeDept, {{"Pname", "Projeto"}, {"Plocation", "Local do Projeto"}})
in
    Renomeado;

shared #"Horas Trabalhadas" = let
    Fonte = MySQL.Database("localhost", "azure_company", [ReturnSingleDatabase = true]),
    works_on = Fonte{[Schema = "azure_company", Item = "works_on"]}[Data],
    Colunas = Table.SelectColumns(works_on, {"Essn", "Pno", "Hours"}),
    Tipos = Table.TransformColumnTypes(Colunas, {{"Essn", type text}, {"Pno", Int64.Type}, {"Hours", type number}}),
    MesclaColab = Table.NestedJoin(Tipos, {"Essn"}, Colaboradores, {"Ssn"}, "C", JoinKind.LeftOuter),
    ExpandeColab = Table.ExpandTableColumn(MesclaColab, "C", {"Colaborador", "Departamento"}),
    MesclaProj = Table.NestedJoin(ExpandeColab, {"Pno"}, Projetos, {"Pnumber"}, "P", JoinKind.LeftOuter),
    ExpandeProj = Table.ExpandTableColumn(MesclaProj, "P", {"Projeto"}),
    Renomeado = Table.RenameColumns(ExpandeProj, {{"Hours", "Horas"}})
in
    Renomeado;
