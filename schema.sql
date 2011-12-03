-- Table `Groups`
CREATE TABLE [Groups] (
[Group] VARCHAR(50)  NULL,
[ArtNum] INTEGER  NULL,
[ID] VARCHAR(50)  NULL
, Time INTEGER);

-- Table `Posts`
CREATE TABLE [Posts] (
[ID] VARCHAR(50)  NULL,
[Message] TEXT  NULL,
[Author] VARCHAR(255)  NULL,
[Subject] VARCHAR(255)  NULL,
[Time] INTEGER  NULL,
[ParentID] VARCHAR(50)  NULL,
[ThreadID] VARCHAR(50)  NULL
);

-- Table `Threads`
CREATE TABLE [Threads] (
[Group] VARCHAR(50)  NULL,
[ID] VARCHAR(50)  NULL,
[LastUpdated] INTEGER  NULL
, LastPost VARCHAR(50));

-- Index `PostThreadID` on table `Posts`
CREATE INDEX [PostThreadID] ON [Posts](
[ThreadID]  ASC
);

-- Index `ThreadGroup` on table `Threads`
CREATE INDEX [ThreadGroup] ON [Threads] ( [Group] );

-- Index `GroupTime` on table `Groups`
CREATE INDEX GroupTime ON Groups (`Group`, Time DESC);

-- Index `ThreadOrder` on table `Threads`
CREATE INDEX ThreadOrder ON Threads ([Group], [LastUpdated] DESC);

-- Index `GroupID` on table `Groups`
CREATE UNIQUE INDEX [GroupID] ON [Groups](
[Group]  ASC,
[ID]  ASC
);

-- Index `PostID` on table `Posts`
CREATE UNIQUE INDEX [PostID] ON "Posts"(
[ID]  ASC
);

-- Index `ThreadID` on table `Threads`
CREATE INDEX "ThreadID" ON "Threads" ( ID );

-- Index `PostParentID` on table `Posts`
CREATE INDEX PostParentID ON Posts ( ParentID );

