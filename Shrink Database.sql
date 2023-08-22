/*==================================================================================
ATIVIDADES ROTINEIRAS B�SICAS DO DBA
SHRINK DATABASE - REDUZINDO TAMANHO DE UMA BASE DE DADOS
==================================================================================*/

USE MASTER
GO

DROP DATABASE IF EXISTS BaseSHRINK 
GO

CREATE DATABASE [BaseSHRINK]
 ON  PRIMARY 
( NAME = N'BaseSHRINK', FILENAME = N'P:\Data\BaseSHRINK.mdf' , SIZE = 3000KB , MAXSIZE = UNLIMITED, FILEGROWTH = 65536KB )
 LOG ON 
( NAME = N'BaseSHRINK_log', FILENAME = N'L:\Log\BaseSHRINK_log.ldf' , SIZE = 512KB , MAXSIZE = 2048GB , FILEGROWTH = 65536KB )
GO

USE BaseSHRINK
GO

DROP TABLE IF EXISTS TABELAREGISTROS
GO

CREATE TABLE TABELAREGISTROS (
	ID INT IDENTITY(1,1) PRIMARY KEY,
	TEXTO1 CHAR (2000),	
	TEXTO2 CHAR (2000),	
	TEXTO3 CHAR (2000),	
	TEXTO4 CHAR (1000),	
	TEXTO5 CHAR (1000),	
)
GO


INSERT INTO TABELAREGISTROS VALUES ('CARREGAMENTO CAMPO TEXTO1','CARREGAMENTO CAMPO TEXTO2','CARREGAMENTO CAMPO TEXTO3','CARREGAMENTO CAMPO TEXTO4','CARREGAMENTO CAMPO TEXTO5')
GO 500000 -- inserir 500 mil registros

-- DADOS NA TABELA
SELECT COUNT(*) FROM TABELAREGISTROS 

-- CHECAR O TAMANHO DOS FILES DO BANCO NO DISCO

--DELETE 300 MIL REGISTRO
DELETE FROM TABELAREGISTROS WHERE ID>300000
go

SELECT COUNT(*) FROM TABELAREGISTROS 
-- Os dados diminuiram mas o SQL deixa os espacos nas paginas de dados para serem utilizadas posteriormente
-- por novos dados a serem inseridos.
-- CHECAR O TAMANHO DOS FILES DE DADOS E DE LOG DO BANCO NO DISCO E NA PROPRIEDADE DO BANCO NO SSMS

-- EVITE OS COMANDOS ABAIXO, PORQUE TRAZEM PERDA DE PERFORMANCE NO SEU AMBIENTE.
-- O PADRAO � ESTAR DESLIGADO O AUTO SHRINK
ALTER DATABASE AULA_SHR SET AUTO_SHRINK OFF --(Desliga)
ALTER DATABASE AULA_SHR SET AUTO_SHRINK ON  --(Liga)

-- Reduzindo o banco de dados de usu�rio BaseSHRINK para permitir 10 por cento de espa�o livre 
-- no banco de dados.

DBCC SHRINKDATABASE (BaseSHRINK, 10); -- IRA REDUZIR TANTO FILE DE DADOS E FILE DE LOG DO BANCO DE DADOS
-- VERIFICAR COMO FICOU O TAMANHO DO BANCO

-- Reduzindo o banco de dados at� a �ltima extens�o alocada.

DBCC SHRINKDATABASE (BaseSHRINK, TRUNCATEONLY);

-- Reduzindo os arquivo de dados e de log

use BaseSHRINK
go
DBCC SHRINKFILE (BaseSHRINK, 10);
DBCC SHRINKFILE (BaseSHRINK_log, 5);

-- CHECAR O TAMANHO DOS FILES DO BANCO NO DISCO

-- Evite diminuir o tamanho dos seus bancos de dados e files, mas quando o fizer
-- fa�a em um momento que tenha pouco acesso ou nenhum acesso e jobs rodando. 
-- Logo ap�s fa�a rebuild de todos os indices ou atualize todas as estatisticas dos indices.

------------------------------- // POR QUE DEVE EVITAR SHRINKDB?

-- Vamos realizar um teste

/*==================================================================================
1.Crie um banco de dados
2.Crie uma tabela de aproximadamente 1 GB com 5 milh�es de linhas
3.Coloque um �ndice clusterizado nele e verifique sua fragmenta��o
4.Olhe para o espa�o vazio do meu banco de dados
5.Reduza o banco de dados para se livrar do espa�o vazio
6.E ent�o veja o que acontece a seguir.
==================================================================================*/

CREATE DATABASE BASETESTE
GO
USE BASETESTE;
GO
ALTER DATABASE BASETESTE SET RECOVERY SIMPLE WITH NO_WAIT
GO
/* Vamos criar uma tabela com 4 milhoes de dados */
SELECT TOP 5000000 o.object_id, m.*
  INTO dbo.Messages
  FROM sys.messages m
  CROSS JOIN sys.all_objects o;
GO
CREATE UNIQUE CLUSTERED INDEX IXnew ON dbo.Messages(object_id, message_id, language_id);
GO

-- E aqui est� o resultado

SELECT * FROM sys.dm_db_index_physical_stats  
    (DB_ID(N'BASETESTE'), OBJECT_ID(N'dbo.Messages'), NULL, NULL , 'DETAILED');  
GO

-- Temos 0,01% de fragmenta��o e 98,19% de cada p�gina de 8 KB est� compactada, sem espaco nas paginas 
-- de dados/indices. 
-- Para performance, � �timo, porque quando formos ler esta tabela, as p�ginas estar�o em ordem 
-- e repletas de dados, sem espacos, possibilitando uma leitura r�pida.

-- AGORA, VAMOS VERIFICAR QUANTO ESPACO LIVRE TEMOS

USE BASETESTE
GO
SELECT 
    [TYPE] = A.TYPE_DESC
    ,[FILE_Name] = A.name
    ,[FILEGROUP_NAME] = fg.name
    ,[File_Location] = A.PHYSICAL_NAME
    ,[FILESIZE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0)
    ,[USEDSPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - ((SIZE/128.0) - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0))
    ,[FREESPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)
    ,[FREESPACE_%] = CONVERT(DECIMAL(10,2),((A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)/(A.SIZE/128.0))*100)
    ,[AutoGrow] = 'By ' + CASE is_percent_growth WHEN 0 THEN CAST(growth/128 AS VARCHAR(10)) + ' MB -' 
        WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '% -' ELSE '' END 
        + CASE max_size WHEN 0 THEN 'DISABLED' WHEN -1 THEN ' Unrestricted' 
            ELSE ' Restricted to ' + CAST(max_size/(128*1024) AS VARCHAR(10)) + ' GB' END 
        + CASE is_percent_growth WHEN 1 THEN ' [autogrowth by percent, BAD setting!]' ELSE '' END
FROM sys.database_files A LEFT JOIN sys.filegroups fg ON A.data_space_id = fg.data_space_id 
order by A.TYPE desc, A.NAME;

-- Como resultados temos>

-- Nosso arquivo de dados est� 50,28% vazio.
-- Bem, isso n�o � bom. Nosso arquivo de dados de 2.442 MB tem 1.277 MB de espa�o livre, por isso est� 50,28% vazio.
-- Ent�o, digamos que queremos recuperar esse espa�o reduzindo o arquivo de dados de volta:

-- iremos deixar 1% de espa�o livre, ou seja o processo ir� reorganizar as paginas de dados 
-- e vai deixar 1% livre (vazia sem dados), mas poderia ser 0%.
DBCC SHRINKDATABASE(BASETESTE, 1); 

-- O arquivo de dados agora est� com 1.226 MB e tem apenas 0,97% de espa�o livre restante. 
-- O arquivo de LOG tamb�m est� reduzido a 24 MB. 
-- Muito Bom !!!!

USE BASETESTE
GO
SELECT 
    [TYPE] = A.TYPE_DESC
    ,[FILE_Name] = A.name
    ,[FILEGROUP_NAME] = fg.name
    ,[File_Location] = A.PHYSICAL_NAME
    ,[FILESIZE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0)
    ,[USEDSPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - ((SIZE/128.0) - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0))
    ,[FREESPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)
    ,[FREESPACE_%] = CONVERT(DECIMAL(10,2),((A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)/(A.SIZE/128.0))*100)
    ,[AutoGrow] = 'By ' + CASE is_percent_growth WHEN 0 THEN CAST(growth/128 AS VARCHAR(10)) + ' MB -' 
        WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '% -' ELSE '' END 
        + CASE max_size WHEN 0 THEN 'DISABLED' WHEN -1 THEN ' Unrestricted' 
            ELSE ' Restricted to ' + CAST(max_size/(128*1024) AS VARCHAR(10)) + ' GB' END 
        + CASE is_percent_growth WHEN 1 THEN ' [autogrowth by percent, BAD setting!]' ELSE '' END
FROM sys.database_files A LEFT JOIN sys.filegroups fg ON A.data_space_id = fg.data_space_id 
order by A.TYPE desc, A.NAME;
GO

-- mas... vamos checar o nivel de fragmentacao da tabela, 
-- usando a mesma querie usada anteriormente

SELECT * FROM sys.dm_db_index_physical_stats  
    (DB_ID(N'BASETESTE'), OBJECT_ID(N'dbo.Messages'), NULL, NULL , 'DETAILED');

-- e como resultamos temos, depois da compacta��o do banco de dados, 98,58% de fragmenta��o, o que � ruim 
-- para performance das opera��es que envolvam consultas no banco de dados.
-- O que o SQL SERVER FAZ PARA COMPACTAR � ir no final no arquivo de dados, copia as paginas de dados 
-- e coloca nos buracos do banco de dados que estavam com espaco livre e agora o banco
-- fica novamente todo fragmentado. Imagino que ter� um job que roda 1 vez por semana ou todo dia, 
-- que verifica os indices que est�o fragmentados e com 98% de fragmenta��o
-- certamente ir� fazer o rebuild ou reorganize os indices cluster (ainda iremos conversar), e assim os 
-- dados nas tabelas serao ordenados novamente para resolver o problema de fragmentacao.

-- Mas, adivinhe o que acontece quando voc� reconstr�i o �ndice?

-- O SQL Server precisa de espa�o vazio suficiente no banco de dados para construir uma c�pia 
-- inteiramente nova do �ndice, ent�o ele ir�:

-- 1. Ampliar o arquivo de dados
-- 2. Usar esse espa�o para construir a nova c�pia do nosso �ndice
-- 3. Eliminar a c�pia antiga do nosso �ndice, deixando um monte de espa�o n�o utilizado no arquivo

-- Vamos verificar isto? Vamos reconstruir o �ndice novamente e verificar a fragmenta��o:

ALTER INDEX IXnew ON dbo.Messages REBUILD;
GO

-- O indice esta novamente desfragmentado
SELECT * FROM sys.dm_db_index_physical_stats  
    (DB_ID(N'BASETESTE'), OBJECT_ID(N'dbo.Messages'), NULL, NULL , 'DETAILED');  
GO

-- Mas retornamos a ter varios espacos livres na tabela

USE BASETESTE
GO
SELECT 
    [TYPE] = A.TYPE_DESC
    ,[FILE_Name] = A.name
    ,[FILEGROUP_NAME] = fg.name
    ,[File_Location] = A.PHYSICAL_NAME
    ,[FILESIZE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0)
    ,[USEDSPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - ((SIZE/128.0) - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0))
    ,[FREESPACE_MB] = CONVERT(DECIMAL(10,2),A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)
    ,[FREESPACE_%] = CONVERT(DECIMAL(10,2),((A.SIZE/128.0 - CAST(FILEPROPERTY(A.NAME, 'SPACEUSED') AS INT)/128.0)/(A.SIZE/128.0))*100)
    ,[AutoGrow] = 'By ' + CASE is_percent_growth WHEN 0 THEN CAST(growth/128 AS VARCHAR(10)) + ' MB -' 
        WHEN 1 THEN CAST(growth AS VARCHAR(10)) + '% -' ELSE '' END 
        + CASE max_size WHEN 0 THEN 'DISABLED' WHEN -1 THEN ' Unrestricted' 
            ELSE ' Restricted to ' + CAST(max_size/(128*1024) AS VARCHAR(10)) + ' GB' END 
        + CASE is_percent_growth WHEN 1 THEN ' [autogrowth by percent, BAD setting!]' ELSE '' END
FROM sys.database_files A LEFT JOIN sys.filegroups fg ON A.data_space_id = fg.data_space_id 
order by A.TYPE desc, A.NAME;

-- CONCLUINDO, COMO DBAS N�O DEVEMOS ENTRAR NESTE CIRCULO VICIOSO.

-- Pare de fazer coisas que causam problemas de desempenho em vez de consert�-los. Se seus bancos de dados t�m algum espa�o vazio neles, tudo bem.
-- O SQL Server provavelmente precisar� desse espa�o novamente para opera��es regulares, como reconstru��es de �ndice ou mesmo para incluis dados novos.
-- SE FOR COMPACTAR, FA�A FORA DO HORARIO COMERCIAL, PORQUE CAUSAR� UM GRANDE IMPACTO NO ACESSO DAS TABELAS, BACKUP, REPLICACAO DE DADOS, ENFIM NO USO DO SISTEMA
-- N�O FA�A A COMPACTA��O DO BANCO DE DADOS (SHRINKDATABASE), MAS SIM DOS FILES ESPEFICICOS, COMO POR EXEMPLO LOG, ATRAVES DO (SHRINKFILES).

-- fonts>
-- https://www.brentozar.com/archive/2017/12/whats-bad-shrinking-databases-dbcc-shrinkdatabase/
-- https://am2.co/2016/04/shrink-database-4-easy-steps/

