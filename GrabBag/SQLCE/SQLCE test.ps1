$binpath = "$pwd\Assemblies";
[Reflection.Assembly]::LoadFile("$binpath\System.Data.SqlServerCe.dll")
$connectionString = "Data Source='C:\temp\testDB.sdf';"
  
$engine = New-Object "System.Data.SqlServerCe.SqlCeEngine" $connectionString
$engine.CreateDatabase()
$engine.Dispose()
 
$connection = New-Object "System.Data.SqlServerCe.SqlCeConnection" $connectionString
$command = New-Object "System.Data.SqlServerCe.SqlCeCommand"
$command.CommandType = [System.Data.CommandType]"Text"
$command.Connection = $connection
 
$connection.Open()
 
$command.CommandText = "CREATE TABLE [Files] ([Id] int NOT NULL  IDENTITY (1,1), [Name] nvarchar(450) NOT NULL);"
$command.ExecuteNonQuery()        
            
$command.CommandText = "ALTER TABLE [Files] ADD CONSTRAINT [PK_Files] PRIMARY KEY ([Id]);"
$command.ExecuteNonQuery()
            
$command.CommandText = "CREATE UNIQUE INDEX [IX_Files_Name] ON [Files] ([Name] ASC);"
$command.ExecuteNonQuery()
 
$command.Dispose()
$connection.Close();
$connection.Dispose;
